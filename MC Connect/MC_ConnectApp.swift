//
//  MC_ConnectApp.swift
//  MC Connect
//
//  Created by Martin Lanius on 22.10.25.
//

import SwiftUI
import SwiftData

@main
struct MC_ConnectApp: App {
    @StateObject private var mqtt = MqttViewModel(service: MqttService())

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(mqtt)
        }
        .modelContainer(for: [Dashboard.self, Widget.self, Device.self])
    }
}
