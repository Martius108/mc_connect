//
//  ChangeWidgetView.swift
//  MC Connect
//
//  Created by Martin Lanius on 24.10.25.
//

import SwiftUI
import SwiftData

struct ChangeWidgetView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Bindable var widget: Widget
    @Bindable var dashboard: Dashboard  // für updatedAt und optionales Löschen

    // Lokale State-Spiegel für Textfelder
    @State private var title: String = ""
    @State private var selectedKind: WidgetKind = .value
    @State private var minValue: String = "0"
    @State private var maxValue: String = "100"
    @State private var unit: String = ""
    @State private var currentValue: String = "0"
    @State private var pinText: String = ""

    // Löschbestätigung
    @State private var showDeleteConfirm = false

    var body: some View {
        NavigationView {
            Form {
                Section("Allgemein") {
                    TextField("Titel", text: $title)
                        .textInputAutocapitalization(.words)
                    Picker("Widget-Art", selection: $selectedKind) {
                        ForEach(WidgetKind.allCases) { kind in
                            Text(kind.rawValue.capitalized).tag(kind)
                        }
                    }
                }

                Section("Werte") {
                    HStack {
                        Text("Aktueller Wert")
                        Spacer()
                        TextField("0", text: $currentValue)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    HStack {
                        Text("Min")
                        Spacer()
                        TextField("0", text: $minValue)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    HStack {
                        Text("Max")
                        Spacer()
                        TextField("100", text: $maxValue)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    HStack {
                        Text("Einheit")
                        Spacer()
                        TextField("z.B. °C, %, V", text: $unit)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 120)
                    }
                }

                Section("Hardware") {
                    HStack {
                        Text("Pin (optional)")
                        Spacer()
                        TextField("z.B. 27", text: $pinText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }
                    if selectedKind == .toggle {
                        Text("Für GPIO-Widgets (z.B. LED/Relais) den GPIO angeben. Beim Pico W ist die Onboard-LED ein spezieller Alias („LED“), kein GPIO.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                Section {
                    Button(role: .destructive) {
                        showDeleteConfirm = true
                    } label: {
                        Label("Widget löschen", systemImage: "trash")
                    }
                }
            }
            .navigationTitle("Widget bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sichern") { saveChanges() }
                        .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear(perform: loadFromWidget)
            .alert("Wirklich löschen?", isPresented: $showDeleteConfirm) {
                Button("Abbrechen", role: .cancel) {}
                Button("Löschen", role: .destructive) { deleteWidget() }
            } message: {
                Text("Dieses Widget wird aus dem Dashboard entfernt.")
            }
        }
    }

    private func loadFromWidget() {
        title = widget.title
        selectedKind = widget.kind
        minValue = String(widget.minValue)
        maxValue = String(widget.maxValue)
        unit = widget.unit
        currentValue = String(widget.value)
        pinText = widget.pin.map { String($0) } ?? ""
    }

    private func saveChanges() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }
        widget.title = cleanTitle
        widget.kind = selectedKind

        widget.minValue = Double(minValue) ?? widget.minValue
        widget.maxValue = Double(maxValue) ?? widget.maxValue
        widget.unit = unit.trimmingCharacters(in: .whitespacesAndNewlines)

        if let val = Double(currentValue) {
            widget.value = val
        }

        let pinTrim = pinText.trimmingCharacters(in: .whitespacesAndNewlines)
        widget.pin = pinTrim.isEmpty ? nil : Int(pinTrim)

        dashboard.updatedAt = Date()
        try? modelContext.save()
        dismiss()
    }

    private func deleteWidget() {
        if let idx = dashboard.widgets.firstIndex(where: { $0.id == widget.id }) {
            dashboard.widgets.remove(at: idx)
        }
        for (i, w) in dashboard.widgets.enumerated() {
            w.order = i
        }
        dashboard.updatedAt = Date()
        modelContext.delete(widget)
        try? modelContext.save()
        dismiss()
    }
}
