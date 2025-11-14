//
//  MC_ConnectApp.swift
//  MC_Connect
//
//  Created by Martin Lanius on 09.11.25.
//

import SwiftUI
import SwiftData

@main
struct MC_ConnectApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Item.self,
            BrokerSettings.self,
            TelemetryConfig.self,
            Device.self,
            TelemetryData.self,
            Dashboard.self,
            Widget.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            // If schema migration fails, try to delete and recreate
            // This handles schema changes that SwiftData can't auto-migrate
            // Delete existing store and try again
            let url = modelConfiguration.url
            try? FileManager.default.removeItem(at: url)
            
            do {
                return try ModelContainer(for: schema, configurations: [modelConfiguration])
            } catch {
                fatalError("Could not create ModelContainer even after reset: \(error)")
            }
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
    }
}
