//
//  DashboardInputView.swift
//  MC Connect
//

import SwiftUI
import SwiftData

struct DashboardInputView: View {
    @Environment(\.dismiss) private var dismiss
    @Query private var devices: [Device]

    @State private var name: String = ""
    @State private var info: String = ""
    @State private var selectedDeviceId: String?

    let onCreate: (String, String?, Device?) -> Void

    var body: some View {
        NavigationView {
            Form {
                Section("Allgemein") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("Beschreibung (optional)", text: $info)
                }

                Section("Gerät") {
                    if devices.isEmpty {
                        Text("Keine Geräte vorhanden")
                            .foregroundColor(.secondary)
                    } else {
                        Picker("Gerät auswählen", selection: $selectedDeviceId) {
                            Text("Keines").tag(nil as String?)
                            ForEach(devices, id: \.id) { device in
                                Text(device.name).tag(device.id as String?)
                            }
                        }
                        .pickerStyle(.inline)
                    }
                }
            }
            .navigationTitle("Neues Dashboard")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Anlegen") {
                        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !n.isEmpty else { return }
                        let i = info.trimmingCharacters(in: .whitespacesAndNewlines)
                        let device = selectedDeviceId.flatMap { id in
                            devices.first { $0.id == id }
                        }
                        onCreate(n, i.isEmpty ? nil : i, device)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
