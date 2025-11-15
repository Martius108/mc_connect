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
            // Automatically reconnect MQTT when app becomes active from background
            if oldPhase == .background && newPhase == .active {
                handleAppBecameActive()
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
        
        // Attempt to reconnect MQTT if needed
        // This will handle the reconnection directly, even if no dashboard is open
        mqttViewModel.attemptReconnectIfNeeded(brokerSettings: settings)
        
        // Also post notification to trigger reconnection in DashboardDetailView
        // This ensures that if a dashboard is open, it will also handle the reconnection
        NotificationCenter.default.post(name: NSNotification.Name("ReconnectMQTT"), object: nil)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Device.self, BrokerSettings.self, TelemetryConfig.self, TelemetryData.self, Dashboard.self, Widget.self], inMemory: true)
}
