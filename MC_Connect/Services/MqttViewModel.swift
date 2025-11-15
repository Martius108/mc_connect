//
//  MqttViewModel.swift
//  MC_Connect
//
//  Created by Martin Lanius on 09.11.25.
//

import Foundation
import SwiftUI
import SwiftData
import Combine

@MainActor
class MqttViewModel: ObservableObject {
    @Published var connectionState: MqttConnectionState = .disconnected
    @Published var latestTelemetryData: [String: [String: TelemetryData]] = [:] // [deviceId: [keyword: TelemetryData]]
    @Published var recentPayloads: [PayloadLogEntry] = [] // Log of recent MQTT payloads
    
    private let mqttService: MqttServiceProtocol
    private var cancellables = Set<AnyCancellable>()
    private var modelContext: ModelContext?
    private let maxLogEntries = 50 // Maximum number of log entries to keep
    private var offlineCheckTimer: Timer?
    private let offlineTimeout: TimeInterval = 30.0 // Mark device as offline after 30 seconds without messages
    
    init(mqttService: MqttServiceProtocol? = nil) {
        self.mqttService = mqttService ?? MqttService()
        setupSubscriptions()
    }
    
    func setModelContext(_ context: ModelContext) {
        self.modelContext = context
    }
    
    private var isSubscribing = false // Flag to prevent multiple simultaneous subscriptions
    
    private var subscribedDevices: [Device] = [] // Track which devices we're subscribed to
    private var subscribedKeywords: [String] = [] // Track which keywords we're subscribed to
    
    private func setupSubscriptions() {
        // Subscribe to connection state changes
        mqttService.connectionState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in
                guard let self = self else { return }
                
                // CRITICAL: Save previous state BEFORE updating
                let previousState = self.connectionState
                
                self.connectionState = newState
                
                // If we were disconnected unexpectedly (error or disconnect), 
                // set all devices to offline
                if case .disconnected = newState {
                    self.setAllDevicesOffline()
                } else if case .error = newState {
                    self.setAllDevicesOffline()
                }
                
                // CRITICAL: When MQTT connects, reset ALL devices to offline first
                // This ensures that devices are only marked as online when they actually send messages
                // This prevents devices from remaining online from a previous session
                if case .connected = newState {
                    // CRITICAL: Check if this is a NEW connection or a RE-connection
                    // If MQTT was already connected (we have data), this is just a state update
                    // and we should NOT clear the data to preserve widget values
                    let wasAlreadyConnected: Bool
                    if case .connected = previousState {
                        wasAlreadyConnected = true
                    } else {
                        wasAlreadyConnected = false
                    }
                    let hasExistingData = !self.latestTelemetryData.isEmpty
                    
                    if wasAlreadyConnected && hasExistingData {
                        // MQTT was already connected and we have data - this is just a state update
                        // Do NOT clear data to preserve widget values when navigating between views
                        return
                    }
                    
                    // CRITICAL: Only clear data if it's empty OR if we're coming from a disconnected state
                    // AND there's no existing data. This preserves widget values when MQTT reconnects
                    // while devices are still online and sending data.
                    // If data already exists, it means devices are actively sending, so preserve it.
                    if hasExistingData {
                        // Data exists - devices are actively sending, preserve the data
                        // Still reset subscribed devices list to prevent conflicts
                        self.subscribedDevices.removeAll()
                        self.subscribedKeywords.removeAll()
                        return
                    }
                    
                    // This is a NEW connection with NO existing data
                    // CRITICAL: Before clearing data, check if there are online devices that might have data in SwiftData
                    // If so, restore their data first to preserve widget values
                    guard let context = self.modelContext else { return }
                    let deviceDescriptor = FetchDescriptor<Device>()
                    guard let allDevices = try? context.fetch(deviceDescriptor) else { return }
                    let previouslyOnlineDeviceIds = allDevices.filter { $0.isOnline }.map { $0.id }
                    
                    // CRITICAL: If there are online devices, restore their data from SwiftData BEFORE clearing
                    // This preserves widget values when MQTT reconnects while devices are still online
                    if !previouslyOnlineDeviceIds.isEmpty {
                        self.restoreTelemetryDataForDevices(deviceIds: previouslyOnlineDeviceIds)
                        
                        // After restoring, check if we now have data
                        let hasDataAfterRestore = !self.latestTelemetryData.isEmpty
                        if hasDataAfterRestore {
                            // Data was restored - preserve it and don't clear
                            // Still reset subscribed devices list to prevent conflicts
                            self.subscribedDevices.removeAll()
                            self.subscribedKeywords.removeAll()
                            return
                        }
                    }
                    
                    // No data could be restored - this is a true fresh connection
                    // Clear data and reset devices
                    self.latestTelemetryData.removeAll()
                    
                    // Reset all devices to offline when connecting
                    // Devices will be marked as online only when they send messages
                    self.setAllDevicesOffline()
                    
                    // CRITICAL: Clear subscribed devices list to prevent auto-resubscription
                    // DashboardDetailView will handle subscriptions manually
                    // This prevents devices from being incorrectly marked as online
                    self.subscribedDevices.removeAll()
                    self.subscribedKeywords.removeAll()
                }
            }
            .store(in: &cancellables)
        
        // Subscribe to incoming messages
        mqttService.receivedMessages
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                self?.handleMessage(message)
                self?.addToLog(topic: message.topic, payload: message.payload)
            }
            .store(in: &cancellables)
    }
    
    private func subscribeToAllDevicesOnConnect() {
        // This function is no longer used - subscriptions are handled manually
        // by DashboardDetailView to prevent conflicts
    }
    
    func connect(brokerSettings: BrokerSettings) -> Bool {
        // Ensure we have a unique client ID to avoid conflicts with other clients
        var clientId = brokerSettings.clientId
        if clientId.isEmpty {
            // Generate a unique client ID with timestamp to avoid conflicts
            clientId = "MC_Connect_\(UUID().uuidString.prefix(8))_\(Int(Date().timeIntervalSince1970))"
        } else {
            // Append timestamp to make it unique even if user provided a static ID
            clientId = "\(clientId)_\(Int(Date().timeIntervalSince1970))"
        }
        
        let config = MqttConfiguration(
            host: brokerSettings.host,
            port: brokerSettings.port,
            username: brokerSettings.username.isEmpty ? nil : brokerSettings.username,
            password: brokerSettings.password.isEmpty ? nil : brokerSettings.password,
            clientId: clientId,
            keepAlive: brokerSettings.keepAlive
        )
        let connected = mqttService.connect(config: config)
        if connected {
            startOfflineCheckTimer()
        }
        return connected
    }
    
    func disconnect() {
        mqttService.disconnect()
        stopOfflineCheckTimer()
        // IMPORTANT: Don't clear telemetry data when disconnecting
        // This allows data to persist when switching tabs or temporarily disconnecting
        // Data will only be cleared on a fresh connection (in setupSubscriptions)
        // latestTelemetryData.removeAll() // Removed to preserve data across tab switches
    }
    
    private func startOfflineCheckTimer() {
        stopOfflineCheckTimer()
        offlineCheckTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let strongSelf = self else { return }
            Task { @MainActor in
                await strongSelf.checkDeviceOfflineStatus()
            }
        }
    }
    
    private func stopOfflineCheckTimer() {
        offlineCheckTimer?.invalidate()
        offlineCheckTimer = nil
    }
    
    private func checkDeviceOfflineStatus() async {
        guard let context = modelContext else { return }
        
        // Only check if MQTT is connected - if disconnected, devices should already be offline
        guard case .connected = connectionState else {
            return
        }
        
        let descriptor = FetchDescriptor<Device>()
        guard let devices = try? context.fetch(descriptor) else { return }
        
        let now = Date()
        let devicesWithMessages = Set(latestTelemetryData.keys)
        var statusChanged = false
        for device in devices {
            // CRITICAL: A device can only be online if:
            // 1. It has sent a message (has lastSeen)
            // 2. It has current telemetry data in latestTelemetryData
            // 3. The last message was within the timeout period
            
            if device.isOnline {
                // Check if device has current telemetry data
                let hasCurrentData = devicesWithMessages.contains(device.id)
                
                if !hasCurrentData {
                    // Device is marked as online but has no current telemetry data
                    // This means it's not sending messages - mark as offline immediately
                    device.isOnline = false
                    device.lastSeen = nil
                    // CRITICAL: Remove in-memory telemetry data
                    latestTelemetryData.removeValue(forKey: device.id)
                    // CRITICAL: Delete all persisted TelemetryData from SwiftData
                    deletePersistedTelemetryData(for: device.id)
                    statusChanged = true
                } else if let lastSeen = device.lastSeen {
                    // Device has sent messages - check if it's been too long
                    let timeSinceLastSeen = now.timeIntervalSince(lastSeen)
                    if timeSinceLastSeen > offlineTimeout {
                        // Too long since last message - mark as offline
                        device.isOnline = false
                        device.lastSeen = nil
                        // CRITICAL: Remove in-memory telemetry data
                        latestTelemetryData.removeValue(forKey: device.id)
                        // CRITICAL: Delete all persisted TelemetryData from SwiftData
                        deletePersistedTelemetryData(for: device.id)
                        statusChanged = true
                    }
                } else {
                    // Device is marked as online but has never sent a message (lastSeen is nil)
                    // This should never happen, but if it does, mark as offline immediately
                    device.isOnline = false
                    // CRITICAL: Remove in-memory telemetry data
                    latestTelemetryData.removeValue(forKey: device.id)
                    // CRITICAL: Delete all persisted TelemetryData from SwiftData
                    deletePersistedTelemetryData(for: device.id)
                    statusChanged = true
                }
            }
            // Note: We don't mark devices as online here - they can only be marked as online
            // when they actually send messages (in handleMessage -> updateDeviceLastSeen)
        }
        
        if statusChanged {
            try? context.save()
            NotificationCenter.default.post(name: NSNotification.Name("DeviceStatusUpdated"), object: nil)
        }
    }
    
    func subscribeToDeviceTelemetry(deviceId: String, keywords: [String]) {
        // Subscribe to the required topics for each device
        // Using QoS 1 for better message delivery guarantee
        let topicsToSubscribe = [
            "device/\(deviceId)/telemetry/#",
            "device/\(deviceId)/status",
            "device/\(deviceId)/ack"
        ]
        _ = mqttService.subscribe(to: topicsToSubscribe, qos: 1)
    }
    
    func subscribeToAllDevices(devices: [Device], telemetryKeywords: [String]) {
        // Prevent multiple simultaneous subscription attempts
        guard !isSubscribing else {
            return
        }
        
        // Store the devices and keywords for auto-resubscription on reconnect
        subscribedDevices = devices
        subscribedKeywords = telemetryKeywords
        
        isSubscribing = true
        
        // CRITICAL: Remove data for devices that are NOT in the new subscription list
        // AND remove data for devices that are in the subscription list but haven't sent messages recently
        // This ensures that only devices actively sending messages have data
        let deviceIdsToSubscribe = Set(devices.map { $0.id })
        let existingDeviceIds = Set(latestTelemetryData.keys)
        
        // Remove data for devices that are no longer in the subscription list
        for deviceId in existingDeviceIds {
            if !deviceIdsToSubscribe.contains(deviceId) {
                latestTelemetryData.removeValue(forKey: deviceId)
            }
        }
        
        // CRITICAL: For devices in the subscription list, verify they have current data
        // If a device is subscribed but has no recent messages, remove its old data
        // This prevents stale data from causing incorrect device status
        // Note: We don't remove data here if the device is subscribed - we let the
        // offline check timer and DashboardDetailView handle that to avoid race conditions
        
        // Subscribe to all devices sequentially to avoid conflicts
        Task { @MainActor in
            for device in devices {
                subscribeToDeviceTelemetry(deviceId: device.id, keywords: telemetryKeywords)
                // Small delay between subscriptions to avoid overwhelming the broker
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
            
            isSubscribing = false
        }
    }
    
    func unsubscribeFromDeviceTelemetry(deviceId: String) {
        // Unsubscribe from all topics for this device
        let topicsToUnsubscribe = [
            "device/\(deviceId)/telemetry/#",
            "device/\(deviceId)/status",
            "device/\(deviceId)/ack"
        ]
        _ = mqttService.unsubscribe(from: topicsToUnsubscribe)
        
        // Remove from subscribed devices list
        subscribedDevices.removeAll { $0.id == deviceId }
        
        // Also remove telemetry data for this device from the dictionary
        latestTelemetryData.removeValue(forKey: deviceId)
        objectWillChange.send()
    }
    
    private func handleMessage(_ message: MqttMessage) {
        let (deviceId, keyword) = message.parseTopic()
        
        // CRITICAL: Validate device ID and keyword before processing
        // This ensures we only process messages from valid devices
        guard let deviceId = deviceId,
              let keyword = keyword,
              !deviceId.isEmpty,
              !keyword.isEmpty else {
            // Invalid topic format - skip this message
            // This prevents processing messages with malformed topics
            return
        }
        
        // CRITICAL: Verify that the device exists in the database before updating status
        // This prevents updating status for non-existent devices
        guard let context = modelContext else { return }
        let deviceDescriptor = FetchDescriptor<Device>(
            predicate: #Predicate<Device> { device in
                device.id == deviceId
            }
        )
        guard let _ = try? context.fetch(deviceDescriptor).first else {
            // Device not found - skip this message
            // This prevents updating status for devices that don't exist
            return
        }
        
        // Handle status topic - check if it's device/{id}/status or device/{id}/telemetry/status
        if keyword == "status" {
            // Check if payload indicates online/offline
            let payloadLower = message.payload.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
            if payloadLower == "online" || payloadLower == "offline" {
                let isOnline = payloadLower == "online"
                updateDeviceStatus(deviceId: deviceId, isOnline: isOnline, updateLastSeen: true)
            } else {
                // For other status messages, just update last seen (device is online if sending messages)
                updateDeviceLastSeen(deviceId: deviceId)
            }
            return
        }
        
        // Handle ack topic - just update device status (device is online if sending messages)
        if keyword == "ack" {
            updateDeviceLastSeen(deviceId: deviceId)
            return
        }
        
        // For telemetry messages (info, summary, temperature, etc.), device is online
        // Update device last seen for any message from the device
        updateDeviceLastSeen(deviceId: deviceId)
        
        // Handle telemetry topics - need a value
        guard let value = message.parseValue() else {
            return
        }
        
        // Get unit from JSON payload first, then from TelemetryConfig, then enum, then empty string
        let unit: String
        if let jsonUnit = message.parseUnit() {
            unit = jsonUnit
        } else if let context = modelContext {
            // Try to get unit from TelemetryConfig
            let descriptor = FetchDescriptor<TelemetryConfig>()
            if let config = try? context.fetch(descriptor).first {
                unit = config.getUnit(for: keyword)
            } else {
                unit = TelemetryKeyword(rawValue: keyword)?.unit ?? ""
            }
        } else {
            unit = TelemetryKeyword(rawValue: keyword)?.unit ?? ""
        }
        
        // Update in-memory dictionary for quick access
        // First, check if we already have this deviceId/keyword combination
        if latestTelemetryData[deviceId] == nil {
            latestTelemetryData[deviceId] = [:]
        }
        
        // Check if we need to update existing data or create new
        // CRITICAL: Always create a NEW TelemetryData object to avoid issues with SwiftData
        // and to ensure we don't accidentally use stale data from previous connections
        let telemetryData: TelemetryData
        let isNewObject: Bool
        
        // CRITICAL: Always create a NEW TelemetryData object instead of updating existing ones
        // This ensures SwiftUI recognizes the change, even when only the value changes
        // Updating existing objects directly doesn't always trigger SwiftUI updates,
        // especially when the dictionary structure changes (e.g., when a new device is added)
        // By creating new objects, we ensure that SwiftUI sees a "new" reference and re-renders
        
        // Always create a new object to ensure SwiftUI detects the change
        telemetryData = TelemetryData(
            deviceId: deviceId,
            keyword: keyword,
            value: value,
            unit: unit,
            timestamp: message.timestamp
        )
        isNewObject = true
        
        // Always update the dictionary to trigger @Published notification
        // CRITICAL: We must create a NEW dictionary structure to ensure SwiftUI detects the change
        // Simply updating nested dictionaries doesn't always trigger @Published notifications
        // IMPORTANT: We must preserve ALL devices and ALL keywords when updating
        // CRITICAL: Read the current state RIGHT BEFORE updating to avoid race conditions
        // This ensures we always work with the most recent data, even if another message
        // updated the dictionary between when we read it earlier and now
        let currentTelemetryData = latestTelemetryData
        
        // Create a completely new top-level dictionary with ALL existing devices preserved
        var newLatestTelemetryData: [String: [String: TelemetryData]] = [:]
        
        // First, copy ALL existing devices and their keywords from the CURRENT state
        // This ensures we don't lose any updates that happened between reading and writing
        for (existingDeviceId, existingKeywords) in currentTelemetryData {
            var deviceKeywords: [String: TelemetryData] = [:]
            // Copy all keywords for this device
            for (existingKeyword, existingData) in existingKeywords {
                deviceKeywords[existingKeyword] = existingData
            }
            newLatestTelemetryData[existingDeviceId] = deviceKeywords
        }
        
        // Now update/add the specific device/keyword we're processing
        if newLatestTelemetryData[deviceId] == nil {
            newLatestTelemetryData[deviceId] = [:]
        }
        newLatestTelemetryData[deviceId]?[keyword] = telemetryData
        
        // Assign the new dictionary to trigger @Published
        latestTelemetryData = newLatestTelemetryData
        
        // Explicitly notify SwiftUI of the change
        // Even though we created a new dictionary, we still call objectWillChange to be safe
        objectWillChange.send()
        
        // Save to SwiftData
        // Note: We only use SwiftData for persistence, but the in-memory dictionary is the source of truth
        // We don't need to sync back from SwiftData - the dictionary is always up-to-date
        if let context = modelContext, isNewObject {
            // Only insert new objects into SwiftData
            // Existing objects are already tracked by SwiftData if they were inserted before
            // If an object exists in the dictionary but not in SwiftData, it means it was created
            // before the context was set, so we insert it now
            context.insert(telemetryData)
            try? context.save()
        }
    }
    
    private func updateDeviceLastSeen(deviceId: String) {
        // When receiving telemetry messages, device is online (it's sending data)
        updateDeviceStatus(deviceId: deviceId, isOnline: true, updateLastSeen: true)
    }
    
    private func updateDeviceStatus(deviceId: String, isOnline: Bool, updateLastSeen: Bool = true) {
        guard let context = modelContext else { return }
        
        // CRITICAL: Use exact match predicate to ensure we only update the specific device
        // This prevents accidentally updating multiple devices
        let descriptor = FetchDescriptor<Device>(
            predicate: #Predicate<Device> { device in
                device.id == deviceId
            }
        )
        
        // CRITICAL: Only update the first matching device (should be exactly one)
        // This ensures we don't accidentally update multiple devices with the same ID
        guard let device = try? context.fetch(descriptor).first else {
            // Device not found - this is fine, just return
            return
        }
        
        // CRITICAL: Double-check that we have the correct device before updating
        guard device.id == deviceId else {
            // Device ID mismatch - this should never happen
            return
        }
        
        // CRITICAL: Only update if status actually changes to avoid unnecessary saves
        let statusChanged = device.isOnline != isOnline
        
        // Update status
        device.isOnline = isOnline
        
        // Update lastSeen timestamp
        if updateLastSeen {
            device.lastSeen = Date()
        }
        
        // Force save to ensure SwiftData updates
        do {
            try context.save()
            // Only notify if status actually changed (not just lastSeen update)
            // This reduces unnecessary UI updates
            if statusChanged {
                NotificationCenter.default.post(name: NSNotification.Name("DeviceStatusUpdated"), object: nil)
            }
        } catch {
            // Failed to save device status - silently continue
        }
    }
    
    func getLatestValue(deviceId: String, keyword: String) -> TelemetryData? {
        return latestTelemetryData[deviceId]?[keyword]
    }
    
    func getAllTelemetryForDevice(deviceId: String) -> [String: TelemetryData] {
        return latestTelemetryData[deviceId] ?? [:]
    }
    
    /// Deletes all TelemetryData objects from SwiftData for a specific device
    /// This ensures that when a device goes offline, all its persisted data is removed
    private func deletePersistedTelemetryData(for deviceId: String) {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<TelemetryData>(
            predicate: #Predicate<TelemetryData> { data in
                data.deviceId == deviceId
            }
        )
        
        if let telemetryData = try? context.fetch(descriptor) {
            for data in telemetryData {
                context.delete(data)
            }
            try? context.save()
        }
    }
    
    /// Deletes all TelemetryData objects from SwiftData for multiple devices
    private func deletePersistedTelemetryData(for deviceIds: [String]) {
        guard modelContext != nil else { return }
        
        for deviceId in deviceIds {
            deletePersistedTelemetryData(for: deviceId)
        }
    }
    
    /// Restores telemetry data from SwiftData for specific devices
    /// This preserves widget values when MQTT reconnects while devices are still online
    func restoreTelemetryDataForDevices(deviceIds: [String]) {
        guard let context = modelContext else { return }
        
        var restoredCount = 0
        
        // For each device, restore its telemetry data from SwiftData
        for deviceId in deviceIds {
            let telemetryDescriptor = FetchDescriptor<TelemetryData>(
                predicate: #Predicate<TelemetryData> { data in
                    data.deviceId == deviceId
                },
                sortBy: [SortDescriptor(\TelemetryData.timestamp, order: .reverse)]
            )
            
            guard let telemetryData = try? context.fetch(telemetryDescriptor) else {
                continue
            }
            
            // Group by keyword and take the most recent for each keyword
            var deviceData: [String: TelemetryData] = [:]
            for data in telemetryData {
                if deviceData[data.keyword] == nil {
                    // Take the first (most recent) entry for each keyword
                    deviceData[data.keyword] = data
                }
            }
            
            // Restore to in-memory dictionary
            if !deviceData.isEmpty {
                latestTelemetryData[deviceId] = deviceData
                restoredCount += 1
            }
        }
        
        if restoredCount > 0 {
            objectWillChange.send()
        }
    }
    
    
    private func addToLog(topic: String, payload: String) {
        let entry = PayloadLogEntry(topic: topic, payload: payload, timestamp: Date())
        recentPayloads.insert(entry, at: 0)
        
        // Keep only the most recent entries
        if recentPayloads.count > maxLogEntries {
            recentPayloads = Array(recentPayloads.prefix(maxLogEntries))
        }
    }
    
    func clearLog() {
        recentPayloads.removeAll()
    }
    
    func publishCommand(topic: String, payload: String) -> Bool {
        guard case .connected = connectionState else {
            return false
        }
        return mqttService.publish(topic: topic, payload: payload, qos: 0)
    }
    
    func setAllDevicesOffline() {
        guard let context = modelContext else { return }
        
        let descriptor = FetchDescriptor<Device>()
        guard let devices = try? context.fetch(descriptor) else { return }
        
        var statusChanged = false
        
        for device in devices {
            // CRITICAL: Mark device as offline AND reset lastSeen
            // This ensures that devices are only marked as online when they actually send messages
            // Resetting lastSeen is important because it prevents devices from being incorrectly
            // marked as online based on stale lastSeen timestamps
            if device.isOnline {
                device.isOnline = false
                statusChanged = true
            }
            // Always reset lastSeen when setting all devices offline
            // This ensures a clean state when MQTT connects
            device.lastSeen = nil
        }
        
        // CRITICAL: Remove all in-memory telemetry data
        // NOTE: We do NOT delete persisted TelemetryData here, as it may be needed
        // to restore widget values when MQTT reconnects. Persisted data will be
        // cleaned up by checkDeviceOfflineStatus() and verifyDeviceStatus() when
        // devices are confirmed to be offline.
        latestTelemetryData.removeAll()
        
        if statusChanged {
            try? context.save()
            NotificationCenter.default.post(name: NSNotification.Name("DeviceStatusUpdated"), object: nil)
        } else {
            // Even if no status changed, save to persist lastSeen = nil
            try? context.save()
        }
    }
    
    
    /// Attempts to reconnect MQTT if disconnected, using devices and telemetry config from SwiftData
    /// This is useful when the app becomes active from background
    func attemptReconnectIfNeeded(brokerSettings: BrokerSettings) {
        // Only reconnect if currently disconnected or in error state
        let shouldReconnect: Bool
        switch connectionState {
        case .disconnected, .error:
            shouldReconnect = true
        case .connecting, .connected:
            shouldReconnect = false
        }
        
        guard shouldReconnect else {
            return
        }
        
        // Check if we have valid broker settings
        guard !brokerSettings.host.isEmpty else {
            return
        }
        
        // Connect to MQTT
        let connected = connect(brokerSettings: brokerSettings)
        
        if connected {
            // Wait for connection, then subscribe to all devices
            Task { @MainActor in
                var attempts = 0
                while case .connecting = connectionState, attempts < 20 {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    attempts += 1
                }
                
                // Check if connected
                if case .connected = connectionState {
                    guard let context = modelContext else { return }
                    
                    // Load telemetry keywords
                    let telemetryDescriptor = FetchDescriptor<TelemetryConfig>()
                    let keywords = (try? context.fetch(telemetryDescriptor).first?.keywords) ?? []
                    
                    // Load all devices
                    let deviceDescriptor = FetchDescriptor<Device>()
                    if let allDevices = try? context.fetch(deviceDescriptor), !allDevices.isEmpty {
                        // Subscribe to all devices
                        subscribeToAllDevices(devices: allDevices, telemetryKeywords: keywords)
                    }
                }
            }
        }
    }
}

// Payload log entry
struct PayloadLogEntry: Identifiable {
    let id = UUID()
    let topic: String
    let payload: String
    let timestamp: Date
}

