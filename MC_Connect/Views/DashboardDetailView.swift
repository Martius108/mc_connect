//
//  DashboardDetailView.swift
//  MC_Connect
//
//  Created by Martin Lanius on 09.11.25.
//

import SwiftUI
import SwiftData

struct DashboardDetailView: View {
    let dashboard: Dashboard
    @Environment(\.modelContext) private var modelContext
    @Query private var devices: [Device]
    @Query private var brokerSettings: [BrokerSettings]
    @Query private var telemetryConfigs: [TelemetryConfig]
    @EnvironmentObject var mqttViewModel: MqttViewModel
    @State private var showingAddWidget = false
    @State private var showingEditWidget: Widget?
    @State private var lastKnownDeviceIds: Set<String> = []
    
    // Computed property to get widgets directly from dashboard
    // This ensures widgets are always up-to-date and don't get lost when view is recreated
    private var widgets: [Widget] {
        dashboard.widgets ?? []
    }
    
    // Grid configuration: 4 columns (quarter width = 1 column, half width = 2 columns, full width = 4 columns)
    private let columns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]
    
    var body: some View {
        return GeometryReader { geometry in
            let screenWidth = max(geometry.size.width, 100) // Ensure minimum width to prevent negative values
            let padding: CGFloat = 16
            let spacing: CGFloat = 16
            let quarterWidth = max((screenWidth - padding * 2 - spacing * 3) / 4, 50) // Ensure minimum width
            let halfWidth = max((screenWidth - padding * 2 - spacing) / 2, 100) // Ensure minimum width
            let fullWidth = max(screenWidth - padding * 2, 200) // Ensure minimum width
            
            ScrollView {
                VStack(alignment: .leading, spacing: spacing) {
                    ForEach(widgetRows, id: \.id) { row in
                        rowView(
                            row: row,
                            quarterWidth: quarterWidth,
                            halfWidth: halfWidth,
                            fullWidth: fullWidth,
                            spacing: spacing
                        )
                    }
                }
                .padding(padding)
            }
        }
        .navigationTitle(dashboard.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    showingAddWidget = true
                } label: {
                    Label("Add Widget", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddWidget) {
            AddWidgetView(dashboard: dashboard)
        }
        .sheet(item: $showingEditWidget) { widget in
            EditWidgetView(dashboard: dashboard, widget: widget)
        }
        .task {
            // CRITICAL: This runs BEFORE the view is rendered (via .task)
            // First, restore telemetry data for online devices if MQTT is already connected
            // This preserves widget values when returning to the dashboard
            // MUST happen BEFORE verifyDeviceStatus() to prevent data deletion
            if case .connected = mqttViewModel.connectionState {
                // Get all devices in this dashboard that are currently online
                let dashboardDeviceIds = Set(dashboard.deviceIds)
                let onlineDevices = devices.filter { dashboardDeviceIds.contains($0.id) && $0.isOnline }
                let onlineDeviceIds = onlineDevices.map { $0.id }
                
                // Check if any online devices are missing telemetry data
                let devicesNeedingRestore = onlineDeviceIds.filter { deviceId in
                    mqttViewModel.latestTelemetryData[deviceId] == nil || mqttViewModel.latestTelemetryData[deviceId]?.isEmpty == true
                }
                
                if !devicesNeedingRestore.isEmpty {
                    mqttViewModel.restoreTelemetryDataForDevices(deviceIds: devicesNeedingRestore)
                }
            }
            
            // Now verify device status AFTER data restoration
            // This ensures that devices with restored data are not incorrectly marked as offline
            await verifyDeviceStatus()
        }
        .onAppear {
            // Check if device list has changed
            let currentDeviceIds = Set(dashboard.deviceIds)
            
            // Initialize lastKnownDeviceIds on first appearance if empty
            if lastKnownDeviceIds.isEmpty {
                lastKnownDeviceIds = currentDeviceIds
            }
            
            let deviceListChanged = currentDeviceIds != lastKnownDeviceIds
            
            if deviceListChanged {
                // Device list changed - do a full refresh
                lastKnownDeviceIds = currentDeviceIds
                autoConnectMQTT()
            } else {
                // Device list unchanged
                // CRITICAL: Only connect if not connected - if already connected, do nothing
                // This prevents unnecessary reconnects that clear telemetry data
                if case .connected = mqttViewModel.connectionState {
                    // Already connected - nothing to do, just check for new devices to subscribe
                    // This ensures that if a device was added while the dashboard was not active,
                    // it will be subscribed when the dashboard becomes active again
                    checkAndSubscribeToNewDevices()
                } else {
                    // Not connected - connect and then subscribe
                    ensureMQTTConnected()
                    
                    // Wait a bit for the connection to be established before checking
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.checkAndSubscribeToNewDevices()
                    }
                }
            }
        }
        .onChange(of: dashboard.deviceIds) { oldIds, newIds in
            // Device list changed - update lastKnownDeviceIds and trigger refresh
            let oldSet = Set(oldIds)
            let newSet = Set(newIds)
            if oldSet != newSet {
                lastKnownDeviceIds = newSet
                // Trigger a full refresh when device list changes
                autoConnectMQTT()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ReconnectMQTT"))) { _ in
            // Reconnect MQTT when device is added or deleted
            reconnectMQTT()
        }
    }
    
    
    @MainActor
    private func verifyDeviceStatus() async {
        // CRITICAL: This runs BEFORE the view is rendered (via .task)
        // Verify device status to ensure only devices with current messages are online
        // This prevents devices from being incorrectly shown as online when the view first appears
        let dashboardDeviceIds = Set(dashboard.deviceIds)
        let dashboardDevices = devices.filter { dashboardDeviceIds.contains($0.id) }
        
        // CRITICAL: Only verify device status if MQTT is connected
        // If MQTT is not connected, we can't determine device status accurately
        // and we should NOT delete data, as it may be restored when MQTT reconnects
        guard case .connected = mqttViewModel.connectionState else {
            return
        }
        
        // Check which devices have current messages in latestTelemetryData
        let devicesWithMessages = Set(mqttViewModel.latestTelemetryData.keys)
        
        var statusChanged = false
        
        for device in dashboardDevices {
            let hasCurrentMessages = devicesWithMessages.contains(device.id)
            
            if !hasCurrentMessages {
                // Device has no current messages - it's truly offline
                // Mark as offline and clean up its data
                if device.isOnline {
                    device.isOnline = false
                    statusChanged = true
                }
                if device.lastSeen != nil {
                    device.lastSeen = nil
                    statusChanged = true
                }
                // CRITICAL: Remove in-memory telemetry data only for offline devices
                mqttViewModel.latestTelemetryData.removeValue(forKey: device.id)
                // CRITICAL: Delete persisted TelemetryData only for offline devices
                deletePersistedTelemetryData(for: device.id)
            } else {
                // Device has current messages - it's online
                // Verify it's marked as online (handleMessage should have done this)
                if !device.isOnline {
                    device.isOnline = true
                    statusChanged = true
                }
                // CRITICAL: Keep all telemetry data for online devices
                // This preserves widget values when returning to the dashboard
                // DO NOT delete data for online devices!
            }
        }
        
        if statusChanged {
            try? modelContext.save()
            NotificationCenter.default.post(name: NSNotification.Name("DeviceStatusUpdated"), object: nil)
        }
    }
    
    /// Deletes all TelemetryData objects from SwiftData for a specific device
    private func deletePersistedTelemetryData(for deviceId: String) {
        let descriptor = FetchDescriptor<TelemetryData>(
            predicate: #Predicate<TelemetryData> { data in
                data.deviceId == deviceId
            }
        )
        
        if let telemetryData = try? modelContext.fetch(descriptor) {
            for data in telemetryData {
                modelContext.delete(data)
            }
            try? modelContext.save()
        }
    }
    
    // Gruppiere Widgets in Zeilen für korrekte Anordnung
    // Berücksichtigt auch die Höhe, um quarter-height Widgets untereinander zu stapeln
    private var widgetRows: [WidgetRow] {
        var rows: [WidgetRow] = []
        var currentRow: [Widget] = []
        var columnPositions: [Int: [Widget]] = [:] // Track which widgets are in which column
        
        for widget in widgets {
            let widgetWidth: Int
            switch widget.widgetWidth {
            case .quarter: widgetWidth = 1
            case .half: widgetWidth = 2
            case .full: widgetWidth = 4
            }
            
            let isQuarterWidget = widget.widgetHeight == .quarter && widget.widgetWidth == .half
            
            // Calculate the actual occupied columns in the row
            // Calculate the rightmost edge of the row (column + width of widgets in that column)
            var rightmostEdge = 0
            if !columnPositions.isEmpty {
                for (colIndex, widgetsInCol) in columnPositions {
                    // Get the maximum width of widgets in this column
                    let maxWidthInColumn = widgetsInCol.map { w in
                        switch w.widgetWidth {
                        case .quarter: return 1
                        case .half: return 2
                        case .full: return 4
                        }
                    }.max() ?? 0
                    // Calculate the right edge of this column
                    let columnRightEdge = colIndex + maxWidthInColumn
                    rightmostEdge = max(rightmostEdge, columnRightEdge)
                }
            }
            
            // Check if row is full (rightmost edge reaches or exceeds 4 columns)
            let rowIsFull = rightmostEdge >= 4
            
            // Check if there's a half-height widget in the current row
            // Quarter-height widgets should only stack if there's a half-height widget in the row
            let hasHalfHeightWidgetInRow = currentRow.contains(where: { $0.widgetHeight == .half })
            
            // Check if we can stack this quarter widget in an existing column
            var canStackInExistingColumn = false
            var targetColumnForStacking: Int? = nil
            if isQuarterWidget {
                // Only allow stacking if there's a half-height widget in the row
                if hasHalfHeightWidgetInRow {
                    // Check all existing columns to see if any has a quarter widget we can stack on
                    for (colIndex, widgetsInCol) in columnPositions {
                        // Count how many quarter-height widgets are already in this column
                        let quarterHeightCount = widgetsInCol.filter { $0.widgetHeight == .quarter }.count
                        
                        // Check if the column width matches the new widget's width
                        let maxWidthInColumn = widgetsInCol.map { w in
                            switch w.widgetWidth {
                            case .quarter: return 1
                            case .half: return 2
                            case .full: return 4
                            }
                        }.max() ?? 0
                        
                        // We can stack if:
                        // 1. The column has at least one quarter-height widget (so we can stack vertically)
                        // 2. The column has fewer than 2 quarter-height widgets (2 quarter = 1 half, so max 2 per column)
                        // 3. The column width matches the new widget width (so they align properly)
                        if quarterHeightCount > 0 && quarterHeightCount < 2 && maxWidthInColumn == widgetWidth {
                            // Found a column with a quarter widget that matches width and has space - we can stack here
                            canStackInExistingColumn = true
                            targetColumnForStacking = colIndex
                            break
                        }
                    }
                }
                // If there's no half-height widget in the row, don't stack - place widgets side by side instead
            }
            
            // Calculate where this widget would be placed if not stacked
            let wouldPlaceAtColumn = rightmostEdge
            let wouldExceedRow = wouldPlaceAtColumn + widgetWidth > 4
            
            // Entscheidungslogik:
            // 1. Wenn die Zeile voll ist (rightmostEdge >= 4) UND wir können nicht stapeln → neue Zeile
            // 2. Wenn das Widget die Zeile überschreiten würde UND wir können nicht stapeln → neue Zeile
            // 3. Wenn ein full-width Widget kommt (nimmt immer eine neue Zeile, außer Zeile ist leer)
            let shouldStartNewRow = (rowIsFull && !canStackInExistingColumn) ||
                                     (!canStackInExistingColumn && wouldExceedRow) ||
                                     (!currentRow.isEmpty && widgetWidth == 4)
            
            if shouldStartNewRow {
                if !currentRow.isEmpty {
                    // Generate stable ID based on first widget ID to prevent unnecessary re-renders
                    // This ensures the row ID stays the same as long as widgets don't change
                    let rowId = currentRow.first?.id ?? UUID()
                    rows.append(WidgetRow(id: rowId, widgets: currentRow, columnPositions: columnPositions))
                }
                currentRow = [widget]
                // Reset column positions for new row
                columnPositions = [0: [widget]]
            } else {
                // Add widget to current row
                currentRow.append(widget)
                
                // Update column positions
                if canStackInExistingColumn, let targetColumn = targetColumnForStacking {
                    // Stack in existing column
                    columnPositions[targetColumn]?.append(widget)
                    // Don't increment width - we're stacking
                } else if !rowIsFull {
                    // Place in new column position only if row is not full
                    let targetColumn = rightmostEdge
                    if columnPositions[targetColumn] == nil {
                        columnPositions[targetColumn] = []
                    }
                    columnPositions[targetColumn]?.append(widget)
                } else {
                    // Row is full but we couldn't stack - this shouldn't happen due to the condition above,
                    // but if it does, place it anyway (shouldn't reach here)
                    let targetColumn = rightmostEdge
                    if columnPositions[targetColumn] == nil {
                        columnPositions[targetColumn] = []
                    }
                    columnPositions[targetColumn]?.append(widget)
                }
            }
        }
        
        // Füge die letzte Zeile hinzu
        if !currentRow.isEmpty {
            // Generate stable ID based on first widget ID to prevent unnecessary re-renders
            // This ensures the row ID stays the same as long as widgets don't change
            let rowId = currentRow.first?.id ?? UUID()
            rows.append(WidgetRow(id: rowId, widgets: currentRow, columnPositions: columnPositions))
        }
        
        return rows
    }
    
    private struct WidgetRow: Identifiable {
        let id: UUID
        let widgets: [Widget]
        let columnPositions: [Int: [Widget]] // Track which widgets are in which column
    }
    
    private func groupWidgetsByColumn(_ widgets: [Widget]) -> [Int: [Widget]] {
        var columnWidgets: [Int: [Widget]] = [:]
        var currentColumn = 0
        
        for widget in widgets {
            let widgetWidth: Int
            switch widget.widgetWidth {
            case .quarter: widgetWidth = 1
            case .half: widgetWidth = 2
            case .full: widgetWidth = 4
            }
            
            if columnWidgets[currentColumn] == nil {
                columnWidgets[currentColumn] = []
            }
            columnWidgets[currentColumn]?.append(widget)
            currentColumn += widgetWidth
        }
        
        return columnWidgets
    }
    
    @ViewBuilder
    private func rowView(row: WidgetRow, quarterWidth: CGFloat, halfWidth: CGFloat, fullWidth: CGFloat, spacing: CGFloat) -> some View {
        // Use the column positions from the row, not recalculate them
        let columnWidgets = row.columnPositions
        
        HStack(alignment: .top, spacing: spacing) {
            // Render each column
            ForEach(Array(columnWidgets.keys.sorted()), id: \.self) { columnIndex in
                if let widgetsInColumn = columnWidgets[columnIndex] {
                    VStack(alignment: .leading, spacing: spacing) {
                        ForEach(widgetsInColumn, id: \.id) { widget in
                            let widgetIndex = row.widgets.firstIndex(where: { $0.id == widget.id }) ?? 0
                            widgetCell(
                                widget: widget,
                                rowWidgets: row.widgets,
                                index: widgetIndex,
                                quarterWidth: quarterWidth,
                                halfWidth: halfWidth,
                                fullWidth: fullWidth,
                                spacing: spacing
                            )
                            .id("\(widget.id)-\(widget.deviceId)-\(widget.telemetryKeyword)")
                        }
                    }
                }
            }
            
            // Fülle die Zeile auf, wenn sie nicht vollständig ist
            let rowWidth = row.widgets.reduce(0) { total, widget in
                switch widget.widgetWidth {
                case .quarter: return total + 1
                case .half: return total + 2
                case .full: return total + 4
                }
            }
            if rowWidth < 4 {
                Spacer()
            }
        }
    }
    
    private func getWidgetWidth(widget: Widget, quarterWidth: CGFloat, halfWidth: CGFloat, fullWidth: CGFloat) -> CGFloat {
        switch widget.widgetWidth {
        case .quarter: return quarterWidth
        case .half: return halfWidth
        case .full: return fullWidth
        }
    }
    
    @ViewBuilder
    private func widgetCell(widget: Widget, rowWidgets: [Widget], index: Int, quarterWidth: CGFloat, halfWidth: CGFloat, fullWidth: CGFloat, spacing: CGFloat) -> some View {
        let widgetWidth = getWidgetWidth(widget: widget, quarterWidth: quarterWidth, halfWidth: halfWidth, fullWidth: fullWidth)
        
        let baseHeight = calculateWidgetHeight(
            widget: widget,
            width: widgetWidth,
            quarterWidth: quarterWidth,
            halfWidth: halfWidth,
            fullWidth: fullWidth,
            spacing: spacing
        )
        
        // Check if this widget should grow to accommodate smaller neighbors
        let widgetHeight = adjustHeightForNeighbors(
            widget: widget,
            rowWidgets: rowWidgets,
            index: index,
            baseHeight: baseHeight,
            quarterWidth: quarterWidth,
            halfWidth: halfWidth,
            spacing: spacing
        )
        
        widgetView(for: widget, width: widgetWidth, height: widgetHeight)
            .frame(width: widgetWidth, height: widgetHeight)
            .contextMenu {
                Button {
                    showingEditWidget = widget
                } label: {
                    Label("Edit", systemImage: "pencil")
                }
                
                Button(role: .destructive) {
                    deleteWidget(widget)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
    }
    
    private func adjustHeightForNeighbors(widget: Widget, rowWidgets: [Widget], index: Int, baseHeight: CGFloat, quarterWidth: CGFloat, halfWidth: CGFloat, spacing: CGFloat) -> CGFloat {
        // Special case: If widget is half width + half height, check if neighbors are quarter height
        guard widget.widgetWidth == .half && widget.widgetHeight == .half else {
            return baseHeight
        }
        
        // Find smaller widgets (quarter height) in the same row
        let smallerNeighbors = rowWidgets.enumerated().filter { neighborIndex, neighborWidget in
            neighborIndex != index &&
            neighborWidget.widgetHeight == .quarter &&
            (neighborWidget.widgetWidth == .half || neighborWidget.widgetWidth == .quarter)
        }
        
        if !smallerNeighbors.isEmpty {
            // Calculate the height needed: two quarter-height widgets + spacing between them
            // This ensures the large widget is tall enough to accommodate two small widgets stacked
            let quarterHeight = quarterWidth
            let twoQuarterHeights = quarterHeight * 2 + spacing
            
            // If base height is less than needed, grow to accommodate
            if baseHeight < twoQuarterHeights {
                return twoQuarterHeights
            }
        }
        
        return baseHeight
    }
    
    private func calculateWidgetHeight(widget: Widget, width: CGFloat, quarterWidth: CGFloat, halfWidth: CGFloat, fullWidth: CGFloat, spacing: CGFloat) -> CGFloat {
        // Basisgröße = halfWidth (quadratisch)
        // Quarter Width + Quarter Height = quarterWidth x quarterWidth (quadratisch, 1/4 Basisgröße)
        // Half Width + Half Height = halfWidth x halfWidth (quadratisch, Basisgröße)
        // Full Width + Half Height = fullWidth x halfWidth (rechteckig, breit aber niedrig)
        // Full Width + Full Height = fullWidth x fullWidth (quadratisch, doppelte Basisgröße)
        // Half Width + Full Height = halfWidth x (halfWidth * 2) (rechteckig, hoch aber schmal)
        
        switch (widget.widgetWidth, widget.widgetHeight) {
        case (.quarter, .quarter):
            // Quarter Width + Quarter Height: quadratisch, 1/4 Basisgröße
            return quarterWidth
        case (.quarter, .half):
            // Quarter Width + Half Height: rechteckig, hoch aber schmal
            return halfWidth
        case (.quarter, .full):
            // Quarter Width + Full Height: rechteckig, sehr hoch aber schmal
            return fullWidth
        case (.half, .quarter):
            // Half Width + Quarter Height: rechteckig, breit aber sehr niedrig
            return quarterWidth
        case (.half, .half):
            // Half Width + Half Height: quadratisch, Basisgröße
            return halfWidth
        case (.half, .full):
            // Half Width + Full Height: rechteckig, hoch aber schmal
            return halfWidth * 2
        case (.full, .quarter):
            // Full Width + Quarter Height: rechteckig, sehr breit aber sehr niedrig
            return quarterWidth
        case (.full, .half):
            // Full Width + Half Height: rechteckig, breit aber niedrig
            return halfWidth
        case (.full, .full):
            // Full Width + Full Height: quadratisch, doppelte Basisgröße
            return fullWidth
        }
    }
    
    private func autoConnectMQTT() {
        // Lade BrokerSettings
        guard let settings = brokerSettings.first else {
            return
        }
        
        // Prüfe ob Settings gültig sind
        guard !settings.host.isEmpty else {
            return
        }
        
        // Wenn bereits verbunden, trenne zuerst (um sicherzustellen, dass nur ein Service läuft)
        // This is a full refresh - disconnect and reconnect to ensure clean state
        if case .connected = mqttViewModel.connectionState {
            mqttViewModel.disconnect()
            // Warte kurz, damit die Disconnection abgeschlossen wird
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.connectMQTT()
            }
        } else {
            connectMQTT()
        }
    }
    
    private func ensureMQTTConnected() {
        // Only connect if not already connected - no disconnect/reconnect cycle
        if case .connected = mqttViewModel.connectionState {
            // Already connected - nothing to do
            // Device status is managed entirely by handleMessage() in MqttViewModel
            return
        }
        
        // Not connected - try to connect
        guard let settings = brokerSettings.first, !settings.host.isEmpty else {
            return
        }
        
        // Connect without disconnecting first (lightweight connection)
        let connected = mqttViewModel.connect(brokerSettings: settings)
        
        if connected {
            // Wait for connection, then subscribe to new devices only
            Task { @MainActor in
                var attempts = 0
                while case .connecting = mqttViewModel.connectionState, attempts < 20 {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    attempts += 1
                }
                
                // Check if connected and subscribe to devices in this dashboard
                if case .connected = mqttViewModel.connectionState {
                    let keywords = telemetryConfigs.first?.keywords ?? []
                    let dashboardDevices = devices.filter { dashboard.deviceIds.contains($0.id) }
                    
                    if !dashboardDevices.isEmpty {
                        mqttViewModel.subscribeToAllDevices(devices: dashboardDevices, telemetryKeywords: keywords)
                    }
                }
            }
        }
    }
    
    private func connectMQTT() {
        guard let settings = brokerSettings.first, !settings.host.isEmpty else {
            return
        }
        
        // Clean up telemetry data for devices that no longer exist before connecting
        let descriptor = FetchDescriptor<Device>()
        if let existingDevices = try? modelContext.fetch(descriptor) {
            let existingDeviceIds = Set(existingDevices.map { $0.id })
            let telemetryDeviceIds = Set(mqttViewModel.latestTelemetryData.keys)
            
            // Remove data for devices that no longer exist
            for deviceId in telemetryDeviceIds {
                if !existingDeviceIds.contains(deviceId) {
                    mqttViewModel.latestTelemetryData.removeValue(forKey: deviceId)
                }
            }
        }
        
        // Verbinde mit MQTT
        let connected = mqttViewModel.connect(brokerSettings: settings)
        
        if connected {
            // Warte auf Verbindung, dann subscribe
            // Use a Combine publisher to wait for connection
            Task { @MainActor in
                // Wait for connection to be established
                var attempts = 0
                while case .connecting = mqttViewModel.connectionState, attempts < 20 {
                    try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                    attempts += 1
                }
                
                // Check if connected
                if case .connected = mqttViewModel.connectionState {
                    // Lade Telemetry-Keywords
                    let keywords = telemetryConfigs.first?.keywords ?? []
                    
                    // Subscribe zu allen Devices
                    // IMPORTANT: Fetch devices again to ensure we have the latest data including newly added devices
                    let descriptor = FetchDescriptor<Device>()
                    if let allDevices = try? modelContext.fetch(descriptor) {
                        // Subscribe zu allen Devices (nicht nur denen im Dashboard)
                        mqttViewModel.subscribeToAllDevices(devices: allDevices, telemetryKeywords: keywords)
                    }
                }
            }
        }
    }
    
    private func reconnectMQTT() {
        // IMPORTANT: Fetch devices from SwiftData to ensure we have the latest data
        let descriptor = FetchDescriptor<Device>()
        guard let existingDevices = try? modelContext.fetch(descriptor) else {
            return
        }
        
        // Check if we're currently connected
        let isCurrentlyConnected: Bool
        if case .connected = mqttViewModel.connectionState {
            isCurrentlyConnected = true
        } else {
            isCurrentlyConnected = false
        }
        
        // Disconnect if connected
        if isCurrentlyConnected {
            mqttViewModel.disconnect()
        }
        
        let existingDeviceIds = Set(existingDevices.map { $0.id })
        let telemetryDeviceIds = Set(mqttViewModel.latestTelemetryData.keys)
        
        // Remove data for devices that no longer exist
        for deviceId in telemetryDeviceIds {
            if !existingDeviceIds.contains(deviceId) {
                mqttViewModel.latestTelemetryData.removeValue(forKey: deviceId)
            }
        }
        
        // Wait for disconnection to complete (if we were connected), then reconnect
        let delay = isCurrentlyConnected ? 1.0 : 0.1
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.connectMQTT()
        }
    }
    
    private func checkAndSubscribeToNewDevices() {
        // Check if there are devices in this dashboard that are not subscribed
        // This is useful if a device was added to the dashboard while it was not active
        guard case .connected = mqttViewModel.connectionState else {
            // Not connected, will be handled by ensureMQTTConnected
            return
        }
        
        // Only check devices that are in this dashboard
        let dashboardDeviceIds = Set(dashboard.deviceIds)
        let dashboardDevices = devices.filter { dashboardDeviceIds.contains($0.id) }
        
        // Get devices that are in the dashboard but not in latestTelemetryData
        let subscribedDeviceIds = Set(mqttViewModel.latestTelemetryData.keys)
        let newDevices = dashboardDevices.filter { !subscribedDeviceIds.contains($0.id) }
        
        if !newDevices.isEmpty {
            // Subscribe to new devices (only those in this dashboard)
            let keywords = telemetryConfigs.first?.keywords ?? []
            mqttViewModel.subscribeToAllDevices(devices: newDevices, telemetryKeywords: keywords)
        }
    }
    
    private func deleteWidget(_ widget: Widget) {
        withAnimation {
            dashboard.widgets?.removeAll { $0.id == widget.id }
            modelContext.delete(widget)
        }
    }
    
    
    @ViewBuilder
    private func widgetView(for widget: Widget, width: CGFloat, height: CGFloat) -> some View {
        // Access latestTelemetryData directly so SwiftUI can observe changes
        // Use a computed property that accesses the @Published property to ensure updates
        // This ensures the view updates when telemetry data changes
        UniversalWidgetView(
            widget: widget,
            mqttViewModel: mqttViewModel
        )
    }
}

struct AddWidgetView: View {
    let dashboard: Dashboard
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var devices: [Device]
    @Query private var telemetryConfigs: [TelemetryConfig]
    
    @State private var title: String = ""
    @State private var selectedWidgetType: WidgetType = .value
    @State private var selectedDeviceId: String = ""
    @State private var selectedKeyword: String = ""
    @State private var unit: String = ""
    @State private var minValue: String = ""
    @State private var maxValue: String = ""
    @State private var selectedWidth: WidgetWidth = .half
    @State private var selectedHeight: WidgetHeight = .half
    @State private var selectedValueStyle: ValueStyle = .analog
    @State private var pin: String = ""
    @State private var selectedPinMode: PinMode? = nil
    @State private var selectedSensorType: SensorType? = nil
    @State private var invertedLogic: Bool = false
    @State private var secondaryKeyword: String = ""
    @State private var secondaryUnit: String = ""
    @State private var temperatureMinValue: String = ""
    @State private var temperatureMaxValue: String = ""
    @State private var humidityMinValue: String = ""
    @State private var humidityMaxValue: String = ""
    @State private var buttonDuration: String = "100"
    
    var availableDevices: [Device] {
        dashboard.deviceIds.compactMap { deviceId in
            devices.first { $0.id == deviceId }
        }
    }
    
    var availableKeywords: [String] {
        telemetryConfigs.first?.keywords ?? []
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Widget Configuration") {
                    TextField("Title", text: $title)
                        .onSubmit { hideKeyboard() }
                    
                    Picker("Widget Type", selection: $selectedWidgetType) {
                        ForEach(WidgetType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    .onChange(of: selectedWidgetType) { _, newType in
                        // Auto-configure special widgets
                        if newType == .klima {
                            selectedWidth = .full
                            selectedHeight = .half
                            selectedKeyword = "temperature"
                            secondaryKeyword = "humidity"
                        } else if newType == .twoValue {
                            selectedWidth = .full
                            selectedHeight = .quarter
                            secondaryKeyword = ""
                        }
                    }
                    
                    Picker("Device", selection: $selectedDeviceId) {
                        Text("Select Device").tag("")
                        ForEach(availableDevices) { device in
                            Text(device.name).tag(device.id)
                        }
                    }
                    
                    if !selectedDeviceId.isEmpty {
                        if selectedWidgetType == .klima {
                            // Klima widget: auto-set to temperature and humidity
                            Text("Temperature: \(selectedKeyword.isEmpty ? "Not set" : selectedKeyword)")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text("Humidity: \(secondaryKeyword.isEmpty ? "Not set" : secondaryKeyword)")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        } else if selectedWidgetType == .twoValue {
                            // Two Value widget: allow selecting two keywords
                            Picker("First Telemetry Keyword", selection: $selectedKeyword) {
                                Text("Select Keyword").tag("")
                                ForEach(availableKeywords, id: \.self) { keyword in
                                    Text(keyword).tag(keyword)
                                }
                            }
                            .onChange(of: selectedKeyword) { _, newKeyword in
                                if let config = telemetryConfigs.first, !newKeyword.isEmpty {
                                    let configUnit = config.getUnit(for: newKeyword)
                                    if unit.isEmpty || unit == TelemetryKeyword(rawValue: selectedKeyword)?.unit {
                                        unit = configUnit
                                    }
                                }
                            }
                            
                            Picker("Second Telemetry Keyword", selection: $secondaryKeyword) {
                                Text("Select Keyword").tag("")
                                ForEach(availableKeywords, id: \.self) { keyword in
                                    Text(keyword).tag(keyword)
                                }
                            }
                            .onChange(of: secondaryKeyword) { _, newKeyword in
                                if let config = telemetryConfigs.first, !newKeyword.isEmpty {
                                    let configUnit = config.getUnit(for: newKeyword)
                                    if secondaryUnit.isEmpty || secondaryUnit == TelemetryKeyword(rawValue: secondaryKeyword)?.unit {
                                        secondaryUnit = configUnit
                                    }
                                }
                            }
                        } else if selectedWidgetType == .button {
                            Picker("Telemetry Keyword", selection: $selectedKeyword) {
                                Text("Select Keyword").tag("")
                                ForEach(availableKeywords, id: \.self) { keyword in
                                    Text(keyword).tag(keyword)
                                }
                            }
                            .onChange(of: selectedKeyword) { _, newKeyword in
                                if let config = telemetryConfigs.first, !newKeyword.isEmpty {
                                    let configUnit = config.getUnit(for: newKeyword)
                                    if unit.isEmpty || unit == TelemetryKeyword(rawValue: selectedKeyword)?.unit {
                                        unit = configUnit
                                    }
                                }
                            }
                        } else {
                            Picker("Telemetry Keyword", selection: $selectedKeyword) {
                                Text("Select Keyword").tag("")
                                ForEach(availableKeywords, id: \.self) { keyword in
                                    Text(keyword).tag(keyword)
                                }
                            }
                            .onChange(of: selectedKeyword) { _, newKeyword in
                                if let config = telemetryConfigs.first, !newKeyword.isEmpty {
                                    let configUnit = config.getUnit(for: newKeyword)
                                    if unit.isEmpty || unit == TelemetryKeyword(rawValue: selectedKeyword)?.unit {
                                        unit = configUnit
                                    }
                                }
                            }
                        }
                    }
                    
                    if selectedWidgetType == .twoValue {
                        TextField("First Unit (optional)", text: $unit)
                            .autocapitalization(.none)
                            .onSubmit { hideKeyboard() }
                        TextField("Second Unit (optional)", text: $secondaryUnit)
                            .autocapitalization(.none)
                            .onSubmit { hideKeyboard() }
                    } else {
                        TextField("Unit (optional)", text: $unit)
                            .autocapitalization(.none)
                            .onSubmit { hideKeyboard() }
                    }
                }
                
                Section("Size") {
                    Picker("Width", selection: $selectedWidth) {
                        ForEach(WidgetWidth.allCases, id: \.self) { width in
                            Text(width.rawValue).tag(width)
                        }
                    }
                    .disabled(selectedWidgetType == .klima || selectedWidgetType == .twoValue)
                    
                    Picker("Height", selection: $selectedHeight) {
                        ForEach(WidgetHeight.allCases, id: \.self) { height in
                            Text(height.rawValue).tag(height)
                        }
                    }
                    .disabled(selectedWidgetType == .klima || selectedWidgetType == .twoValue)
                }
                
                if selectedWidgetType == .gauge || selectedWidgetType == .progress || selectedWidgetType == .slider {
                    Section("Range") {
                        TextField("Min Value (default: 0)", text: $minValue)
                            .keyboardType(.decimalPad)
                            .onSubmit { hideKeyboard() }
                        TextField("Max Value (default: 100)", text: $maxValue)
                            .keyboardType(.decimalPad)
                            .onSubmit { hideKeyboard() }
                    }
                }
                
                if selectedWidgetType == .klima {
                    Section("Temperature Range") {
                        TextField("Min Value (default: 0)", text: $temperatureMinValue)
                            .keyboardType(.decimalPad)
                        TextField("Max Value (default: 100)", text: $temperatureMaxValue)
                            .keyboardType(.decimalPad)
                    }
                    
                    Section("Humidity Range") {
                        TextField("Min Value (default: 0)", text: $humidityMinValue)
                            .keyboardType(.decimalPad)
                        TextField("Max Value (default: 100)", text: $humidityMaxValue)
                            .keyboardType(.decimalPad)
                    }
                }
                
                
                if selectedWidgetType == .switchType {
                    Section("Switch Configuration") {
                        TextField("PIN Number", text: $pin)
                            .keyboardType(.numberPad)
                            .onSubmit { hideKeyboard() }
                        
                        Picker("Pin Mode", selection: $selectedPinMode) {
                            Text("Select Mode").tag(PinMode?.none)
                            ForEach(PinMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(PinMode?.some(mode))
                            }
                        }
                        
                        Toggle("Inverted Logic", isOn: $invertedLogic)
                    }
                }
                
                if selectedWidgetType == .slider {
                    Section("Slider Configuration") {
                        TextField("PIN Number", text: $pin)
                            .keyboardType(.numberPad)
                            .onSubmit { hideKeyboard() }
                        
                        Picker("Pin Mode", selection: $selectedPinMode) {
                            Text("Select Mode").tag(PinMode?.none)
                            ForEach(PinMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(PinMode?.some(mode))
                            }
                        }
                    }
                }
                
                if selectedWidgetType == .button {
                    Section("Button Configuration") {
                        TextField("PIN Number", text: $pin)
                            .keyboardType(.numberPad)
                            .onSubmit { hideKeyboard() }
                        
                        Picker("Pin Mode", selection: $selectedPinMode) {
                            Text("Select Mode").tag(PinMode?.none)
                            ForEach(PinMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(PinMode?.some(mode))
                            }
                        }
                        
                        Toggle("Inverted Logic", isOn: $invertedLogic)
                        
                        TextField("Press Duration (ms, default: 100)", text: $buttonDuration)
                            .keyboardType(.numberPad)
                            .onSubmit { hideKeyboard() }
                    }
                }
                
                if selectedWidgetType == .sensorAnalog || selectedWidgetType == .sensorBinary {
                    Section("Sensor Configuration") {
                        TextField("PIN Number", text: $pin)
                            .keyboardType(.numberPad)
                            .onSubmit { hideKeyboard() }
                        
                        Picker("Sensor Type", selection: $selectedSensorType) {
                            Text("Select Type").tag(SensorType?.none)
                            ForEach(SensorType.allCases, id: \.self) { type in
                                Text(type.rawValue).tag(SensorType?.some(type))
                            }
                        }
                        
                        Toggle("Inverted Logic", isOn: $invertedLogic)
                        
                        if selectedWidgetType == .sensorAnalog {
                            Section("Range") {
                                TextField("Min Value", text: $minValue)
                                    .keyboardType(.decimalPad)
                                    .onSubmit { hideKeyboard() }
                                TextField("Max Value", text: $maxValue)
                                    .keyboardType(.decimalPad)
                                    .onSubmit { hideKeyboard() }
                            }
                        } else {
                            Section("Threshold") {
                                TextField("Min Value (LOW)", text: $minValue)
                                    .keyboardType(.decimalPad)
                                    .onSubmit { hideKeyboard() }
                                TextField("Max Value (HIGH)", text: $maxValue)
                                    .keyboardType(.decimalPad)
                                    .onSubmit { hideKeyboard() }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Widget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        hideKeyboard()
                        saveWidget()
                    }
                    .disabled(!isValid)
                }
            }
        }
    }
    
    private var isValid: Bool {
        if selectedWidgetType == .klima {
            return !title.isEmpty && !selectedDeviceId.isEmpty
        } else if selectedWidgetType == .twoValue {
            return !title.isEmpty && !selectedDeviceId.isEmpty && !selectedKeyword.isEmpty && !secondaryKeyword.isEmpty
        } else {
            return !title.isEmpty && !selectedDeviceId.isEmpty && !selectedKeyword.isEmpty
        }
    }
    
    private func saveWidget() {
        // Get unit from TelemetryConfig if not manually set
        let finalUnit: String
        if !unit.isEmpty {
            finalUnit = unit
        } else if let config = telemetryConfigs.first {
            finalUnit = config.getUnit(for: selectedKeyword)
        } else {
            finalUnit = TelemetryKeyword(rawValue: selectedKeyword)?.unit ?? ""
        }
        
        // Get secondary unit from TelemetryConfig if not manually set (for twoValue widgets)
        let finalSecondaryUnit: String?
        if selectedWidgetType == .twoValue {
            if !secondaryUnit.isEmpty {
                finalSecondaryUnit = secondaryUnit
            } else if let config = telemetryConfigs.first, !secondaryKeyword.isEmpty {
                finalSecondaryUnit = config.getUnit(for: secondaryKeyword)
            } else {
                finalSecondaryUnit = TelemetryKeyword(rawValue: secondaryKeyword)?.unit
            }
        } else {
            finalSecondaryUnit = nil
        }
        
        let widget = Widget(
            title: title,
            widgetType: selectedWidgetType,
            deviceId: selectedDeviceId,
            telemetryKeyword: selectedKeyword,
            unit: finalUnit,
            minValue: Double(minValue),
            maxValue: Double(maxValue),
            width: selectedWidth,
            height: selectedHeight,
            valueStyle: selectedWidgetType == .value || selectedWidgetType == .twoValue ? selectedValueStyle : nil,
            pin: Int(pin),
            pinMode: selectedPinMode,
            sensorType: selectedSensorType,
            invertedLogic: invertedLogic,
            secondaryTelemetryKeyword: secondaryKeyword.isEmpty ? nil : secondaryKeyword,
            secondaryUnit: finalSecondaryUnit,
            temperatureMinValue: selectedWidgetType == .klima ? Double(temperatureMinValue) : nil,
            temperatureMaxValue: selectedWidgetType == .klima ? Double(temperatureMaxValue) : nil,
            humidityMinValue: selectedWidgetType == .klima ? Double(humidityMinValue) : nil,
            humidityMaxValue: selectedWidgetType == .klima ? Double(humidityMaxValue) : nil,
            buttonDuration: selectedWidgetType == .button ? Double(buttonDuration) : nil
        )
        
        if dashboard.widgets == nil {
            dashboard.widgets = []
        }
        dashboard.widgets?.append(widget)
        modelContext.insert(widget)
        
        dismiss()
    }
}

struct EditWidgetView: View {
    let dashboard: Dashboard
    let widget: Widget
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var devices: [Device]
    @Query private var telemetryConfigs: [TelemetryConfig]
    
    @State private var title: String = ""
    @State private var selectedWidgetType: WidgetType = .value
    @State private var selectedDeviceId: String = ""
    @State private var selectedKeyword: String = ""
    @State private var unit: String = ""
    @State private var minValue: String = ""
    @State private var maxValue: String = ""
    @State private var selectedWidth: WidgetWidth = .half
    @State private var selectedHeight: WidgetHeight = .half
    @State private var selectedValueStyle: ValueStyle = .analog
    @State private var pin: String = ""
    @State private var selectedPinMode: PinMode? = nil
    @State private var selectedSensorType: SensorType? = nil
    @State private var invertedLogic: Bool = false
    @State private var secondaryKeyword: String = ""
    @State private var secondaryUnit: String = ""
    @State private var temperatureMinValue: String = ""
    @State private var temperatureMaxValue: String = ""
    @State private var humidityMinValue: String = ""
    @State private var humidityMaxValue: String = ""
    @State private var buttonDuration: String = "100"
    
    var availableDevices: [Device] {
        dashboard.deviceIds.compactMap { deviceId in
            devices.first { $0.id == deviceId }
        }
    }
    
    var availableKeywords: [String] {
        telemetryConfigs.first?.keywords ?? []
    }
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Widget Configuration") {
                    TextField("Title", text: $title)
                        .onSubmit { hideKeyboard() }
                    
                    Picker("Widget Type", selection: $selectedWidgetType) {
                        ForEach(WidgetType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                    
                    Picker("Device", selection: $selectedDeviceId) {
                        Text("Select Device").tag("")
                        ForEach(availableDevices) { device in
                            Text(device.name).tag(device.id)
                        }
                    }
                    
                    if !selectedDeviceId.isEmpty {
                        if selectedWidgetType == .klima {
                            // Klima widget: auto-set to temperature and humidity
                            Text("Temperature: \(selectedKeyword.isEmpty ? "Not set" : selectedKeyword)")
                                .foregroundColor(.secondary)
                                .font(.caption)
                            Text("Humidity: \(secondaryKeyword.isEmpty ? "Not set" : secondaryKeyword)")
                                .foregroundColor(.secondary)
                                .font(.caption)
                        } else if selectedWidgetType == .twoValue {
                            // Two Value widget: allow selecting two keywords
                            Picker("First Telemetry Keyword", selection: $selectedKeyword) {
                                Text("Select Keyword").tag("")
                                ForEach(availableKeywords, id: \.self) { keyword in
                                    Text(keyword).tag(keyword)
                                }
                            }
                            .onChange(of: selectedKeyword) { _, newKeyword in
                                if let config = telemetryConfigs.first, !newKeyword.isEmpty {
                                    let configUnit = config.getUnit(for: newKeyword)
                                    if unit.isEmpty || unit == TelemetryKeyword(rawValue: selectedKeyword)?.unit {
                                        unit = configUnit
                                    }
                                }
                            }
                            
                            Picker("Second Telemetry Keyword", selection: $secondaryKeyword) {
                                Text("Select Keyword").tag("")
                                ForEach(availableKeywords, id: \.self) { keyword in
                                    Text(keyword).tag(keyword)
                                }
                            }
                            .onChange(of: secondaryKeyword) { _, newKeyword in
                                if let config = telemetryConfigs.first, !newKeyword.isEmpty {
                                    let configUnit = config.getUnit(for: newKeyword)
                                    if secondaryUnit.isEmpty || secondaryUnit == TelemetryKeyword(rawValue: secondaryKeyword)?.unit {
                                        secondaryUnit = configUnit
                                    }
                                }
                            }
                        } else if selectedWidgetType == .button {
                            Picker("Telemetry Keyword", selection: $selectedKeyword) {
                                Text("Select Keyword").tag("")
                                ForEach(availableKeywords, id: \.self) { keyword in
                                    Text(keyword).tag(keyword)
                                }
                            }
                            .onChange(of: selectedKeyword) { _, newKeyword in
                                if let config = telemetryConfigs.first, !newKeyword.isEmpty {
                                    let configUnit = config.getUnit(for: newKeyword)
                                    if unit.isEmpty || unit == TelemetryKeyword(rawValue: selectedKeyword)?.unit {
                                        unit = configUnit
                                    }
                                }
                            }
                        } else {
                            Picker("Telemetry Keyword", selection: $selectedKeyword) {
                                Text("Select Keyword").tag("")
                                ForEach(availableKeywords, id: \.self) { keyword in
                                    Text(keyword).tag(keyword)
                                }
                            }
                            .onChange(of: selectedKeyword) { _, newKeyword in
                                if let config = telemetryConfigs.first, !newKeyword.isEmpty {
                                    let configUnit = config.getUnit(for: newKeyword)
                                    if unit.isEmpty || unit == TelemetryKeyword(rawValue: selectedKeyword)?.unit {
                                        unit = configUnit
                                    }
                                }
                            }
                        }
                    }
                    
                    if selectedWidgetType == .twoValue {
                        TextField("First Unit (optional)", text: $unit)
                            .autocapitalization(.none)
                            .onSubmit { hideKeyboard() }
                        TextField("Second Unit (optional)", text: $secondaryUnit)
                            .autocapitalization(.none)
                            .onSubmit { hideKeyboard() }
                    } else {
                        TextField("Unit (optional)", text: $unit)
                            .autocapitalization(.none)
                            .onSubmit { hideKeyboard() }
                    }
                }
                
                Section("Size") {
                    Picker("Width", selection: $selectedWidth) {
                        ForEach(WidgetWidth.allCases, id: \.self) { width in
                            Text(width.rawValue).tag(width)
                        }
                    }
                    .disabled(selectedWidgetType == .klima || selectedWidgetType == .twoValue)
                    
                    Picker("Height", selection: $selectedHeight) {
                        ForEach(WidgetHeight.allCases, id: \.self) { height in
                            Text(height.rawValue).tag(height)
                        }
                    }
                    .disabled(selectedWidgetType == .klima || selectedWidgetType == .twoValue)
                }
                
                if selectedWidgetType == .gauge || selectedWidgetType == .progress || selectedWidgetType == .slider {
                    Section("Range") {
                        TextField("Min Value (default: 0)", text: $minValue)
                            .keyboardType(.decimalPad)
                            .onSubmit { hideKeyboard() }
                        TextField("Max Value (default: 100)", text: $maxValue)
                            .keyboardType(.decimalPad)
                            .onSubmit { hideKeyboard() }
                    }
                }
                
                if selectedWidgetType == .klima {
                    Section("Temperature Range") {
                        TextField("Min Value (default: 0)", text: $temperatureMinValue)
                            .keyboardType(.decimalPad)
                        TextField("Max Value (default: 100)", text: $temperatureMaxValue)
                            .keyboardType(.decimalPad)
                    }
                    
                    Section("Humidity Range") {
                        TextField("Min Value (default: 0)", text: $humidityMinValue)
                            .keyboardType(.decimalPad)
                        TextField("Max Value (default: 100)", text: $humidityMaxValue)
                            .keyboardType(.decimalPad)
                    }
                }
                
                
                if selectedWidgetType == .switchType {
                    Section("Switch Configuration") {
                        TextField("PIN Number", text: $pin)
                            .keyboardType(.numberPad)
                            .onSubmit { hideKeyboard() }
                        
                        Picker("Pin Mode", selection: $selectedPinMode) {
                            Text("Select Mode").tag(PinMode?.none)
                            ForEach(PinMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(PinMode?.some(mode))
                            }
                        }
                        
                        Toggle("Inverted Logic", isOn: $invertedLogic)
                    }
                }
                
                if selectedWidgetType == .slider {
                    Section("Slider Configuration") {
                        TextField("PIN Number", text: $pin)
                            .keyboardType(.numberPad)
                            .onSubmit { hideKeyboard() }
                        
                        Picker("Pin Mode", selection: $selectedPinMode) {
                            Text("Select Mode").tag(PinMode?.none)
                            ForEach(PinMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(PinMode?.some(mode))
                            }
                        }
                    }
                }
                
                if selectedWidgetType == .button {
                    Section("Button Configuration") {
                        TextField("PIN Number", text: $pin)
                            .keyboardType(.numberPad)
                            .onSubmit { hideKeyboard() }
                        
                        Picker("Pin Mode", selection: $selectedPinMode) {
                            Text("Select Mode").tag(PinMode?.none)
                            ForEach(PinMode.allCases, id: \.self) { mode in
                                Text(mode.rawValue).tag(PinMode?.some(mode))
                            }
                        }
                        
                        Toggle("Inverted Logic", isOn: $invertedLogic)
                        
                        TextField("Press Duration (ms, default: 100)", text: $buttonDuration)
                            .keyboardType(.numberPad)
                            .onSubmit { hideKeyboard() }
                    }
                }
                
                if selectedWidgetType == .sensorAnalog || selectedWidgetType == .sensorBinary {
                    Section("Sensor Configuration") {
                        TextField("PIN Number", text: $pin)
                            .keyboardType(.numberPad)
                            .onSubmit { hideKeyboard() }
                        
                        Picker("Sensor Type", selection: $selectedSensorType) {
                            Text("Select Type").tag(SensorType?.none)
                            ForEach(SensorType.allCases, id: \.self) { type in
                                Text(type.rawValue).tag(SensorType?.some(type))
                            }
                        }
                        
                        Toggle("Inverted Logic", isOn: $invertedLogic)
                        
                        if selectedWidgetType == .sensorAnalog {
                            Section("Range") {
                                TextField("Min Value", text: $minValue)
                                    .keyboardType(.decimalPad)
                                    .onSubmit { hideKeyboard() }
                                TextField("Max Value", text: $maxValue)
                                    .keyboardType(.decimalPad)
                                    .onSubmit { hideKeyboard() }
                            }
                        } else {
                            Section("Threshold") {
                                TextField("Min Value (LOW)", text: $minValue)
                                    .keyboardType(.decimalPad)
                                    .onSubmit { hideKeyboard() }
                                TextField("Max Value (HIGH)", text: $maxValue)
                                    .keyboardType(.decimalPad)
                                    .onSubmit { hideKeyboard() }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Edit Widget")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        hideKeyboard()
                        saveWidget()
                    }
                    .disabled(!isValid)
                }
            }
            .onAppear {
                title = widget.title
                selectedWidgetType = widget.type
                selectedDeviceId = widget.deviceId
                selectedKeyword = widget.telemetryKeyword
                unit = widget.unit
                minValue = widget.minValue != nil ? String(widget.minValue!) : ""
                maxValue = widget.maxValue != nil ? String(widget.maxValue!) : ""
                selectedWidth = widget.widgetWidth
                selectedHeight = widget.widgetHeight
                selectedValueStyle = widget.style ?? .analog
                pin = widget.pin != nil ? String(widget.pin!) : ""
                selectedPinMode = widget.mode
                selectedSensorType = widget.sensorTypeEnum
                invertedLogic = widget.invertedLogic
                secondaryKeyword = widget.secondaryTelemetryKeyword ?? ""
                secondaryUnit = widget.secondaryUnit ?? ""
                temperatureMinValue = widget.temperatureMinValue != nil ? String(widget.temperatureMinValue!) : ""
                temperatureMaxValue = widget.temperatureMaxValue != nil ? String(widget.temperatureMaxValue!) : ""
                humidityMinValue = widget.humidityMinValue != nil ? String(widget.humidityMinValue!) : ""
                humidityMaxValue = widget.humidityMaxValue != nil ? String(widget.humidityMaxValue!) : ""
                buttonDuration = widget.buttonDuration != nil ? String(Int(widget.buttonDuration!)) : "100"
            }
        }
    }
    
    private var isValid: Bool {
        if selectedWidgetType == .klima {
            return !title.isEmpty && !selectedDeviceId.isEmpty
        } else if selectedWidgetType == .twoValue {
            return !title.isEmpty && !selectedDeviceId.isEmpty && !selectedKeyword.isEmpty && !secondaryKeyword.isEmpty
        } else {
            return !title.isEmpty && !selectedDeviceId.isEmpty && !selectedKeyword.isEmpty
        }
    }
    
    private func saveWidget() {
        // Get unit from TelemetryConfig if not manually set
        let finalUnit: String
        if !unit.isEmpty {
            finalUnit = unit
        } else if let config = telemetryConfigs.first {
            finalUnit = config.getUnit(for: selectedKeyword)
        } else {
            finalUnit = TelemetryKeyword(rawValue: selectedKeyword)?.unit ?? ""
        }
        
        widget.title = title
        widget.type = selectedWidgetType
        widget.deviceId = selectedDeviceId
        widget.telemetryKeyword = selectedKeyword
        widget.unit = finalUnit
        widget.minValue = Double(minValue)
        widget.maxValue = Double(maxValue)
        widget.widgetWidth = selectedWidth
        widget.widgetHeight = selectedHeight
        widget.style = selectedWidgetType == .value || selectedWidgetType == .twoValue ? selectedValueStyle : nil
        widget.pin = Int(pin)
        widget.mode = selectedPinMode
        widget.sensorTypeEnum = selectedSensorType
        widget.invertedLogic = invertedLogic
        widget.secondaryTelemetryKeyword = secondaryKeyword.isEmpty ? nil : secondaryKeyword
        
        // Get secondary unit from TelemetryConfig if not manually set (for twoValue widgets)
        if selectedWidgetType == .twoValue {
            if !secondaryUnit.isEmpty {
                widget.secondaryUnit = secondaryUnit
            } else if let config = telemetryConfigs.first, !secondaryKeyword.isEmpty {
                widget.secondaryUnit = config.getUnit(for: secondaryKeyword)
            } else {
                widget.secondaryUnit = TelemetryKeyword(rawValue: secondaryKeyword)?.unit
            }
        } else {
            widget.secondaryUnit = nil
        }
        
        // Set separate temperature/humidity min/max values for klima widgets
        if selectedWidgetType == .klima {
            widget.temperatureMinValue = Double(temperatureMinValue)
            widget.temperatureMaxValue = Double(temperatureMaxValue)
            widget.humidityMinValue = Double(humidityMinValue)
            widget.humidityMaxValue = Double(humidityMaxValue)
        } else {
            widget.temperatureMinValue = nil
            widget.temperatureMaxValue = nil
            widget.humidityMinValue = nil
            widget.humidityMaxValue = nil
        }
        
        // Set button duration for button widgets
        widget.buttonDuration = selectedWidgetType == .button ? Double(buttonDuration) : nil
        
        dismiss()
    }
}
