//
//  DashboardInputView.swift
//  MC Connect
//
//  Created by Martin Lanius on 23.10.25.
//

import SwiftUI
import SwiftData

struct DashboardInputView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
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
                        createDashboardAndPersist()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                // Wenn genau ein Device vorhanden ist, automatisch auswählen (UX)
                if devices.count == 1 && selectedDeviceId == nil {
                    selectedDeviceId = devices.first?.id
                }
            }
        }
    }

    // MARK: - Create & persist Dashboard
    private func createDashboardAndPersist() {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }
        let i = info.trimmingCharacters(in: .whitespacesAndNewlines)

        // Find selected device object (if any)
        let device = selectedDeviceId.flatMap { id in
            devices.first { $0.id == id }
        }

        // Create Dashboard model instance and set deviceId
        // NOTE: Assumes Dashboard(name:) initializer exists in your model.
        let dash = Dashboard(name: n)
        dash.info = i.isEmpty ? nil : i
        dash.deviceId = device?.id
        dash.createdAt = Date()
        dash.updatedAt = Date()

        // Persist immediate in modelContext to ensure deviceId is stored
        modelContext.insert(dash)
        do {
            try modelContext.save()
            print("Dashboard created with deviceId = \(dash.deviceId ?? "nil")")
        } catch {
            print("Fehler beim Speichern des Dashboards: \(error)")
        }

        // Call existing callback for compatibility
        onCreate(n, i.isEmpty ? nil : i, device)

        dismiss()
    }
}
