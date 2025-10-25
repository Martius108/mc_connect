//
//  WidgetInputView.swift
//  MC Connect
//
//  Created by Martin Lanius on 24.10.25.
//

import SwiftUI
import SwiftData

struct WidgetInputView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    let dashboard: Dashboard

    @State private var title: String = ""
    @State private var selectedKind: WidgetKind = .value
    @State private var topic: String = ""
    @State private var minValue: String = "0"
    @State private var maxValue: String = "100"
    @State private var unit: String = ""
    @State private var initialValue: String = "0"
    @State private var pinText: String = ""     // ← NEU

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

                Section("MQTT") {
                    TextField("Topic (optional)", text: $topic)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Text("Beispiel: device/pico01/telemetry/temp")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Section("Werte") {
                    HStack {
                        Text("Startwert")
                        Spacer()
                        TextField("0", text: $initialValue)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    HStack {
                        Text("Min")
                        Spacer()
                        TextField("0", text: $minValue)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }

                    HStack {
                        Text("Max")
                        Spacer()
                        TextField("100", text: $maxValue)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
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
                        TextField("z.B. 25", text: $pinText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                    }
                    if selectedKind == .toggle {
                        Text("Für GPIO-Widgets (z.B. LED) den Pin angeben. Beim Pico W ist die Onboard-LED i. d. R. Pin 25.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .navigationTitle("Widget hinzufügen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Hinzufügen") {
                        addWidget()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func addWidget() {
        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanTitle.isEmpty else { return }

        let cleanTopic = topic.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTopic = cleanTopic.isEmpty ? nil : cleanTopic

        let min = Double(minValue) ?? 0
        let max = Double(maxValue) ?? 100
        let initial = Double(initialValue) ?? 0
        let cleanUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)

        let nextOrder = (dashboard.widgets.map(\.order).max() ?? -1) + 1
        let pin = Int(pinText.trimmingCharacters(in: .whitespacesAndNewlines)) // nil wenn leer/ungültig

        let widget = Widget(
            title: cleanTitle,
            value: initial,
            minValue: min,
            maxValue: max,
            unit: cleanUnit,
            kind: selectedKind,
            topic: finalTopic,
            order: nextOrder,
            pin: pin
        )

        dashboard.widgets.append(widget)
        dashboard.updatedAt = Date()

        try? modelContext.save()
        dismiss()
    }
}
