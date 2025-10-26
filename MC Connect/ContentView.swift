//
//  ContentView.swift
//  MC Connect
//
//  Created by Martin Lanius on 23.10.25.
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var mqtt: MqttViewModel

    var body: some View {
        TabView {
            DashboardView()
                .tabItem { Label("Dashboard", systemImage: "square.grid.3x3.fill") }

            DevicesView()
                .tabItem { Label("Devices", systemImage: "cpu.fill") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
    }
}

#Preview {
    // Preview benötigt ein environmentObject, sonst Crash
    ContentView()
        .environmentObject(MqttViewModel(service: MqttService()))
}
