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
    @Environment(\.dismiss) private var dismiss

    @Bindable var device: Device   // SwiftData @Model binding

    @Query private var dashboards: [Dashboard] // zum Bereinigen beim Löschen

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

            // Telemetry entfernt wie gewünscht

            Section {
                Button(role: .destructive) {
                    deleteDevice()
                } label: {
                    HStack {
                        Image(systemName: "trash")
                        Text("Löschen")
                    }
                }
            }
        }
        .navigationTitle(device.name)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Abbrechen") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Speichern") {
                    saveChanges()
                }
            }
        }
    }

    // MARK: - Aktionen (bestehende Methoden unverändert belassen)

    private func connectToDevice() async {
        isProcessing = true

        // Prüfen, ob bereits ein anderes Device verbunden ist
        if mqtt.isConnected, let currentId = mqtt.connectedDeviceId, currentId != device.id {
            // Alert entfernt — Funktion belassen
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

    // MARK: - Save / Delete

    private func saveChanges() {
        do {
            try modelContext.save()
        } catch {
            print("Fehler beim Speichern des Devices: \(error)")
        }
        dismiss()
    }

    // Delete device (ohne Alert)
    private func deleteDevice() {
        isProcessing = true

        // Falls derzeit verbunden mit diesem Device -> trennen
        if mqtt.isConnected, mqtt.connectedDeviceId == device.id {
            mqtt.disconnect()
        }

        // Dashboards bereinigen, die diese deviceId haben
        for d in dashboards where d.deviceId == device.id {
            d.deviceId = ""
            d.updatedAt = Date()
        }

        // Device löschen
        modelContext.delete(device)

        do {
            try modelContext.save()
        } catch {
            print("Fehler beim Löschen des Devices: \(error)")
        }

        isProcessing = false
        dismiss()
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
