//
//  ContentView.swift
//  MC Connect
//
//  Created by Martin Lanius on 23.10.25.
//

import SwiftUI

struct ContentView: View {
    
    @StateObject private var mqttVM = MqttViewModel(service: MqttService())

    var body: some View {
        TabView {
            DashboardView()
                .environmentObject(mqttVM)
                .tabItem { Label("Dashboard", systemImage: "square.grid.3x3.fill") }

            DevicesView()
                .environmentObject(mqttVM)
                .tabItem { Label("Devices", systemImage: "cpu.fill") }

            SettingsView()
                .environmentObject(mqttVM)
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

#Preview {
    ContentView()
}
