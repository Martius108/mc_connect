//
//  ContentView.swift
//  MC_Connect
//
//  Created by Martin Lanius on 09.11.25.
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var mqttViewModel = MqttViewModel()
    @Environment(\.scenePhase) private var scenePhase
    @Query private var brokerSettings: [BrokerSettings]
    @Query private var dashboards: [Dashboard]
    @Query private var devices: [Device]

    var body: some View {
        TabView {
            DashboardsView()
                .tabItem {
                    Label("Dashboards", systemImage: "chart.bar.fill")
                }
            
            DevicesView()
                .tabItem {
                    Label("Devices", systemImage: "cpu.fill")
                }
            
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape.fill")
                }
        }
        .environmentObject(mqttViewModel)
        .onAppear {
            mqttViewModel.setModelContext(modelContext)
            
            // Check if MQTT is not connected and set all devices to offline
            // This ensures that when the app starts, devices don't show as online
            // if there's no active MQTT connection
            if case .connected = mqttViewModel.connectionState {
                // Connected - devices will be updated by incoming messages
            } else {
                // Not connected - set all devices to offline immediately
                mqttViewModel.setAllDevicesOffline()
            }
        }
        .onChange(of: scenePhase) { oldPhase, newPhase in
            // Handle app lifecycle changes for MQTT connection
            switch (oldPhase, newPhase) {
            case (.active, .inactive):
                // App is going to inactive (e.g., screen lock)
                // Don't disconnect MQTT - let iOS handle the connection
                // The connection may be suspended but will be restored when app becomes active
                break
            case (.inactive, .background):
                // App is now in background
                // Still don't disconnect - iOS may keep the connection alive briefly
                break
            case (.background, .inactive):
                // App is coming back from background
                break
            case (.inactive, .active), (.background, .active):
                // App is becoming active again (e.g., screen unlock)
                // Check and restore MQTT connection if needed
                handleAppBecameActive()
            default:
                break
            }
        }
    }
    
    private func handleAppBecameActive() {
        // Check if we have valid broker settings
        guard let settings = brokerSettings.first,
              !settings.host.isEmpty else {
            return
        }
        
        // Check if there are any devices to monitor
        // Only reconnect if there are devices to monitor
        let hasDevicesInDashboards = dashboards.contains { dashboard in
            !dashboard.deviceIds.isEmpty && 
            dashboard.deviceIds.contains { deviceId in
                devices.contains { $0.id == deviceId }
            }
        }
        
        // Also check if there are any devices at all
        let hasAnyDevices = !devices.isEmpty
        
        guard hasDevicesInDashboards || hasAnyDevices else {
            return
        }
        
        // CRITICAL: Check if MQTT is still connected after screen lock/background
        // iOS may have suspended the connection, so we need to verify and restore if needed
        let isConnected: Bool
        if case .connected = mqttViewModel.connectionState {
            isConnected = true
        } else {
            isConnected = false
        }
        
        if !isConnected {
            // Connection was lost (likely due to iOS suspension) - attempt to reconnect
            mqttViewModel.attemptReconnectIfNeeded(brokerSettings: settings)
            
            // Also post notification to trigger reconnection in DashboardDetailView
            // This ensures that if a dashboard is open, it will also handle the reconnection
            NotificationCenter.default.post(name: NSNotification.Name("ReconnectMQTT"), object: nil)
        } else {
            // Connection appears to be active - verify subscriptions are still working
            // Post notification to let DashboardDetailView verify and restore subscriptions if needed
            NotificationCenter.default.post(name: NSNotification.Name("VerifyMQTTConnection"), object: nil)
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Device.self, BrokerSettings.self, TelemetryConfig.self, TelemetryData.self, Dashboard.self, Widget.self], inMemory: true)
}
