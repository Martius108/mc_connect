//
//  DevicesView.swift
//  MC Connect
//
//  Created by Martin Lanius on 23.10.25.
//

import SwiftUI

struct DevicesView: View {
    @EnvironmentObject var mqtt: MqttViewModel
    @State private var ledOn: Bool = false   // Lokaler UI-Status

    var body: some View {
        NavigationView {
            List {
                Section("Pico W") {
                    HStack {
                        Text("Status")
                        Spacer()
                        ConnectionStatusDot(connected: mqtt.isConnected)
                        Text(mqtt.connectionState.rawValue)
                            .foregroundColor(.secondary)
                    }

                    HStack(spacing: 12) {
                        // LED ON
                        Button(action: {
                            guard mqtt.isConnected else { return }
                            mqtt.publish(topic: "pi/cmd", json: ["target":"led", "value": 1])
                            ledOn = true
                        }) {
                            Text("LED ON")
                                .frame(maxWidth: .infinity)
                        }
                        .applyPrimaryStyle(isActive: ledOn, color: .blue)
                        .disabled(!mqtt.isConnected)

                        // LED OFF
                        Button(action: {
                            guard mqtt.isConnected else { return }
                            mqtt.publish(topic: "pi/cmd", json: ["target":"led", "value": 0])
                            ledOn = false
                        }) {
                            Text("LED OFF")
                                .frame(maxWidth: .infinity)
                        }
                        .applyPrimaryStyle(isActive: !ledOn, color: .blue)
                        .disabled(!mqtt.isConnected)
                    }

                    HStack {
                        Text("LED")
                        Spacer()
                        Text(ledOn ? "ON" : "OFF")
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(ledOn ? .blue : .secondary)
                    }
                }
            }
            .navigationTitle("Devices")
        }
    }
}

// MARK: - Kompatible Button Styles

// Ein schlanker „bordered“ Look, der auf allen Targets läuft
struct BorderedButtonStyleCompat: ButtonStyle {
    var foreground: Color = .accentColor
    var borderColor: Color = .accentColor

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .foregroundColor(foreground)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(borderColor.opacity(configuration.isPressed ? 0.6 : 1.0), lineWidth: 1)
            )
            .opacity(configuration.isPressed ? 0.8 : 1.0)
    }
}

// Ein „borderedProminent“-ähnlicher Look (gefüllt, dunkelblau bei aktiv)
struct BorderedProminentButtonStyleCompat: ButtonStyle {
    var background: Color = .blue
    var foreground: Color = .white

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .foregroundColor(foreground)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(background.opacity(configuration.isPressed ? 0.85 : 1.0))
            )
    }
}

// Bequemer Modifier, um je nach Aktivität zu wechseln
extension View {
    func applyPrimaryStyle(isActive: Bool, color: Color) -> some View {
        Group {
            if isActive {
                self.buttonStyle(BorderedProminentButtonStyleCompat(background: color, foreground: .white))
            } else {
                self.buttonStyle(BorderedButtonStyleCompat(foreground: color, borderColor: color))
            }
        }
    }
}
