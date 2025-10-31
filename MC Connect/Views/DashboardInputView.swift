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
    // Wir speichern hier die externe Device-ID (externalId) als Auswahl
    @State private var selectedDeviceExternalId: String?

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
                        Picker("Gerät auswählen", selection: $selectedDeviceExternalId) {
                            // Wenn du Dashboards ohne Device erlauben möchtest, kannst du hier "Keines" belassen.
                            // Da dashboard.deviceId jetzt non-optional ist, forciere ich hier die Auswahl eines Geräts.
                            Text("Bitte Gerät wählen").tag(nil as String?)
                            ForEach(devices, id: \.id) { device in
                                // Zeige Hinweis, falls externalId leer ist.
                                if device.externalId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text("\(device.name) — fehlt Device ID")
                                        .foregroundColor(.secondary)
                                        .tag(nil as String?)
                                } else {
                                    Text("\(device.name) (\(device.externalId))")
                                        .tag(device.externalId as String?)
                                }
                            }
                        }
                        .pickerStyle(.inline)

                        // Hinweis, wenn ein Gerät ohne externalId ausgewählt wurde (sollte eigentlich verhindert sein)
                        if let selected = selectedDeviceExternalId, selected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            Text("Das ausgewählte Gerät hat keine Device ID. Bitte wähle ein Gerät mit gültiger Device ID.")
                                .foregroundColor(.red)
                                .font(.caption)
                        }
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
                    .disabled(!canCreate)
                }
            }
            .onAppear {
                // Wenn genau ein Device vorhanden ist, automatisch auswählen (UX)
                if devices.count == 1 && selectedDeviceExternalId == nil {
                    // Wähle nur, wenn das Device eine externalId hat
                    let ext = devices.first?.externalId.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    selectedDeviceExternalId = ext.isEmpty ? nil : ext
                }
            }
        }
    }

    // MARK: - Validierung: Name & Device Auswahl (mit gültiger externalId) erforderlich
    private var canCreate: Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        guard let sel = selectedDeviceExternalId else { return false }
        return !sel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Create & persist Dashboard
    private func createDashboardAndPersist() {
        let n = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !n.isEmpty else { return }

        guard let selectedExternal = selectedDeviceExternalId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !selectedExternal.isEmpty else {
            print("[DashboardInputView] Kein gültiges Gerät ausgewählt (externalId fehlt)")
            return
        }

        // Find selected device object (if any) by externalId
        let device = devices.first { $0.externalId == selectedExternal }

        // Create Dashboard model instance and set deviceId = externalId
        let dash = Dashboard(name: n)
        dash.info = info.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : info.trimmingCharacters(in: .whitespacesAndNewlines)
        dash.deviceId = selectedExternal // externalId ist jetzt die deviceId, nicht optional
        dash.createdAt = Date()
        dash.updatedAt = Date()

        // Persist immediate in modelContext to ensure deviceId is stored
        modelContext.insert(dash)
        do {
            try modelContext.save()
            print("Dashboard created with deviceId = \(dash.deviceId)")
        } catch {
            print("Fehler beim Speichern des Dashboards: \(error)")
        }

        // Call existing callback for compatibility (returns the selected Device object as well)
        onCreate(n, dash.info, device)

        dismiss()
    }
}
