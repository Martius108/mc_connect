//
//  SettingsView.swift
//  MC Connect
//
//  Created by Martin Lanius on 23.10.25.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var mqtt: MqttViewModel

    var body: some View {
        NavigationView {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("MQTT: \(mqtt.connectionState.rawValue)")
                        .font(.headline)
                        .foregroundColor(mqtt.connectionState == .connected ? .green : .secondary)
                    Spacer()
                    Button(mqtt.isConnected ? "Disconnect" : "Connect") {
                        mqtt.isConnected ? mqtt.disconnect() : mqtt.connect()
                    }
                    .buttonStyle(.borderedProminent)
                }

                Text("Messages").font(.headline)
                List(mqtt.messages.reversed(), id: \.id) { msg in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(msg.topic)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Text(msg.payload)
                            .font(.body.monospaced())
                            .lineLimit(3)
                    }
                }
            }
            .padding()
            .navigationTitle("Settings")
        }
    }
}
