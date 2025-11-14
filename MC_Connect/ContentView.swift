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
    }
}

#Preview {
    ContentView()
        .modelContainer(for: [Device.self, BrokerSettings.self, TelemetryConfig.self, TelemetryData.self, Dashboard.self, Widget.self], inMemory: true)
}
