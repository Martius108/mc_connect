//
//  DeviceDetailView.swift
//  MC Connect
//
//  Created by Martin Lanius on 25.10.25.
//

import SwiftUI
import SwiftData
import CocoaMQTT

struct DeviceDetailView: View {
    @EnvironmentObject var mqtt: MqttViewModel
    @Environment(\.modelContext) private var modelContext

    @Bindable var device: Device   // SwiftData @Model binding

    @State private var ledOn: Bool = false
    @State private var showAlert = false
    @State private var isProcessing = false

    var body: some View {
        Form {
            Section("Allgemein") {
                TextField("Name", text: $device.name)
                TextField("Typ", text: $device.type)
            }

            Section("Broker / Auth") {
                TextField("Host", text: $device.host)
                    .textContentType(.URL)

                TextField("Port", value: $device.port, format: .number)
                    .keyboardType(.numberPad)

                TextField("Username", text: $device.username)
                SecureField("Password", text: $device.password)
            }

            Section("Connection") {
                HStack {
                    Text("Broker Status")
                    Spacer()
                    ConnectionStatusDot(connected: mqtt.isConnected)
                    Text(mqtt.connectionState.rawValue)
                        .foregroundColor(.secondary)
                }

                HStack {
                    Button(action: {
                        Task {
                            await connectToDevice()
                        }
                    }) {
                        Text("Verbinden")
                    }
                    .disabled(isProcessing || mqtt.isConnected)

                    Spacer()

                    Button(action: {
                        disconnect()
                    }) {
                        Text("Trennen")
                            .foregroundColor(.red)
                    }
                    .disabled(isProcessing || !mqtt.isConnected)
                }
            }

            Section("Actions") {
                HStack(spacing: 12) {
                    Button {
                        Task {
                            await mqtt.publishAsync(topic: "pi/cmd", json: ["target": "led", "value": 1])
                            await MainActor.run { ledOn = true }
                        }
                    } label: {
                        Text("LED ON")
                            .frame(maxWidth: .infinity)
                    }
                    .applyPrimaryStyle(isActive: ledOn, color: Color.blue)
                    .disabled(!mqtt.isConnected)

                    Button {
                        Task {
                            await mqtt.publishAsync(topic: "pi/cmd", json: ["target": "led", "value": 0])
                            await MainActor.run { ledOn = false }
                        }
                    } label: {
                        Text("LED OFF")
                            .frame(maxWidth: .infinity)
                    }
                    .applyPrimaryStyle(isActive: !ledOn, color: Color.blue)
                    .disabled(!mqtt.isConnected)
                }

                HStack {
                    Text("LED Status")
                    Spacer()
                    Text(ledOn ? "ON" : "OFF")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(ledOn ? .blue : .secondary)
                }
            }

            Section("Telemetry") {
                if let state = mqtt.lastKnownLedState(for: device.id) {
                    Text("Letzter LED-State: \(state ? "ON" : "OFF")")
                        .foregroundColor(.secondary)
                } else {
                    Text("Letzte Telemetrie: -")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle(device.name)
        .onAppear {
            if let state = mqtt.lastKnownLedState(for: device.id) {
                ledOn = state
            }
        }
        .onReceive(mqtt.$lastLedStateByDevice) { map in
            if let state = map[device.id] {
                ledOn = state
            }
        }
        .alert("Achtung", isPresented: $showAlert) {
            Button("Abbrechen", role: .cancel) { }
            Button("Trotzdem verbinden") {
                mqtt.disconnect()
                Task {
                    await connectToDevice()
                }
            }
        } message: {
            Text("Ein anderes Device ist bereits verbunden. Möchtest du die Verbindung wechseln?")
        }
    }

    // MARK: - Aktionen

    private func connectToDevice() async {
        isProcessing = true

        // Prüfen, ob bereits ein anderes Device verbunden ist
        if mqtt.isConnected, let currentId = mqtt.connectedDeviceId, currentId != device.id {
            showAlert = true
            isProcessing = false
            return
        }

        // Erzeuge eine eindeutige Client-ID
        let uniqueClientID = "ios-\(UUID().uuidString.prefix(8))"

        // Setze Config mit eindeutiger Client-ID
        mqtt.setConfig(
            host: device.host,
            port: device.port,
            clientID: uniqueClientID,
            username: device.username,
            password: device.password
        )

        // Starte Verbindung
        mqtt.connect(for: device.id)

        // Subscribe auf feste Topics mit QoS
        mqtt.subscribe(topic:"pi/cmd", qos: .qos1)
        mqtt.subscribe(topic:"pi/telemetry", qos: .qos1)
        mqtt.subscribe(topic:"pi/ack", qos: .qos1)

        isProcessing = false
    }

    private func disconnect() {
        isProcessing = true
        mqtt.disconnect()
        isProcessing = false
    }
}

// MARK: - Button Styles

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
