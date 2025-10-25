//
//  DeviceInputView.swift
//  MC Connect
//
//  Created by Martin Lanius on 25.10.25.
//

import SwiftUI

struct DeviceInputView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var type: String = "pico"
    @State private var host: String = "broker.hivemq.com"
    @State private var port: String = "1883"
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var clientID: String = "ios-\(UUID().uuidString.prefix(8))"
    @State private var commandTopic: String = "pi/cmd"
    @State private var telemetryTopic: String = "pi/telemetry"
    @State private var ackTopic: String = "pi/ack"

    var onSave: (Device) -> Void

    var body: some View {
        NavigationView {
            Form {
                Section("Allgemein") {
                    TextField("Name", text: $name)
                    TextField("Typ (pico/esp32)", text: $type)
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
                        guard let p = Int(port) else { return }
                        let dev = Device(
                            name: name.isEmpty ? "Device" : name,
                            type: type,
                            host: host,
                            port: p,
                            username: username,
                            password: password,
                            clientID: clientID,
                            commandTopic: commandTopic,
                            telemetryTopic: telemetryTopic,
                            ackTopic: ackTopic,
                            isActive: false
                        )
                        onSave(dev)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || host.isEmpty || clientID.isEmpty)
                }
            }
        }
    }
}
