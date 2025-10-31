//
//  DeviceInputView.swift
//  MC Connect
//
//  Created by Martin Lanius on 25.10.25.
//

import SwiftUI
import SwiftData

struct DeviceInputView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var type: String = ""
    @State private var externalId: String = ""
    @State private var host: String = "192.168.178.25"
    @State private var port: String = "1883"
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var clientID: String = "ios-\(UUID().uuidString.prefix(8))"
    @State private var commandTopic: String = "pi/cmd"
    @State private var telemetryTopic: String = "pi/telemetry"
    @State private var ackTopic: String = "pi/ack"

    // Callback(s) vom Aufrufer — Parent macht das Persistieren
    var onSave: (Device) -> Void
    var onCreate: (Device) -> Void

    var body: some View {
        NavigationView {
            Form {
                Section("Allgemein") {
                    TextField("Name", text: $name)
                    TextField("Typ (pico/esp32)", text: $type)
                    TextField("Device ID", text: $externalId)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                    if externalId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        Text("Device ID darf nicht leer sein")
                            .foregroundColor(.red)
                            .font(.caption)
                    }
                }

                Section("Broker") {
                    TextField("Host", text: $host)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                    TextField("Username", text: $username)
                    SecureField("Password", text: $password)
                    TextField("Client ID", text: $clientID)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("Topics") {
                    TextField("Command Topic", text: $commandTopic)
                    TextField("Telemetry Topic", text: $telemetryTopic)
                    TextField("ACK Topic", text: $ackTopic)
                }
            }
            .navigationTitle("Neues Device")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        createAndReturnDevice()
                    }
                    .disabled(!canSave)
                }
            }
        }
    }

    private var canSave: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard !host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        guard Int(port.trimmingCharacters(in: .whitespacesAndNewlines)) != nil else { return false }
        guard !clientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        // externalId must not be empty
        guard !externalId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return true
    }

    private func createAndReturnDevice() {
        // Safety: validate again
        let trimmedExternalId = externalId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedExternalId.isEmpty else { return }
        guard let p = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }

        let dev = Device(
            id: UUID().uuidString,
            name: name.isEmpty ? "Device" : name,
            type: type,
            host: host.trimmingCharacters(in: .whitespacesAndNewlines),
            port: p,
            username: username.trimmingCharacters(in: .whitespacesAndNewlines),
            password: password,
            clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines),
            commandTopic: commandTopic.trimmingCharacters(in: .whitespacesAndNewlines),
            telemetryTopic: telemetryTopic.trimmingCharacters(in: .whitespacesAndNewlines),
            ackTopic: ackTopic.trimmingCharacters(in: .whitespacesAndNewlines),
            externalId: trimmedExternalId,
            isActive: false // Parent entscheidet, ob aktiv
        )

        // Gib das Device an den Parent zurück; Parent ist verantwortlich für insert/save und ggf. isActive setzen.
        onSave(dev)
        onCreate(dev) // falls du separate Logik brauchst; sonst kann Parent onCreate leer lassen

        // Dismiss das Sheet
        dismiss()
    }
}
