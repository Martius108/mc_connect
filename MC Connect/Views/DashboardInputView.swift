//
//  DashboardInputView.swift
//  MC Connect
//
//  Created by Martin Lanius on 24.10.25.
//

import SwiftUI

struct DashboardInputView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name: String = ""
    @State private var info: String = ""

    let onCreate: (String, String?) -> Void

    var body: some View {
        NavigationView {
            Form {
                Section("Allgemein") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)
                    TextField("Beschreibung (optional)", text: $info)
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
                        onCreate(n, i.isEmpty ? nil : i)
                        dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
