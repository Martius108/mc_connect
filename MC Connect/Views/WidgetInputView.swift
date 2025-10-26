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
    @State private var pinText: String = ""

    // Neue Felder passend zum aktualisierten Widget-Model
    @State private var stepText: String = ""
    @State private var maxHistoryPointsText: String = ""
    @State private var formatText: String = ""
    @State private var refreshIntervalText: String = ""
    @State private var debounceMsText: String = ""
    @State private var invert: Bool = false
    @State private var optionsText: String = "" // CSV für picker/options

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
                    // Startwert nur für Output-Widgets
                    if selectedKind.isOutput {
                        HStack {
                            Text("Startwert")
                            Spacer()
                            TextField("0", text: $initialValue)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                    }

                    // min/max nur für numerische Widgets (sensorAnalog, gauge, slider, progress, value, servo)
                    if selectedKind.isNumeric {
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
                    }

                    HStack {
                        Text("Einheit")
                        Spacer()
                        TextField("z.B. °C, %, V", text: $unit)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 140)
                    }

                    // Schrittweite für Slider/Servo
                    if selectedKind == .slider || selectedKind == .servo {
                        HStack {
                            Text("Schrittweite")
                            Spacer()
                            TextField("z.B. 1", text: $stepText)
                                .keyboardType(.decimalPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
                    }
                }

                // Options / Picker
                if selectedKind == .picker {
                    Section("Optionen") {
                        TextField("Optionen (CSV)", text: $optionsText)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        Text("Beispiel: auto,manual,off")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Chart / Telemetry settings
                if selectedKind == .chart || selectedKind == .sensorAnalog {
                    Section("Telemetry / Chart") {
                        HStack {
                            Text("Refresh (s)")
                            Spacer()
                            TextField("z.B. 5", text: $refreshIntervalText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }

                        HStack {
                            Text("Max History Punkte")
                            Spacer()
                            TextField("z.B. 200", text: $maxHistoryPointsText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }

                        HStack {
                            Text("Format")
                            Spacer()
                            TextField("%.1f °C", text: $formatText)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 140)
                        }
                    }
                }

                // Hardware / Pin
                Section("Hardware") {
                    HStack {
                        Text("Pin (optional)")
                        Spacer()
                        TextField("z.B. 25", text: $pinText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 100)
                    }

                    Toggle("Invertierte Logik (active-low)", isOn: $invert)

                    if selectedKind.isOutput {
                        Text("Für GPIO-Widgets (z. B. LED) den Pin angeben. Beim Pico W ist die Onboard-LED i. d. R. Pin 25.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else if selectedKind.isInput {
                        Text("Gib den Pin an, von dem der Sensor liest (z. B. 26).")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                // Debounce für digitale Sensoren
                if selectedKind == .sensorBinary {
                    Section("Sensor") {
                        HStack {
                            Text("Debounce (ms)")
                            Spacer()
                            TextField("z.B. 50", text: $debounceMsText)
                                .keyboardType(.numberPad)
                                .multilineTextAlignment(.trailing)
                                .frame(width: 100)
                        }
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
        let initial = selectedKind.isOutput ? (Double(initialValue) ?? 0) : 0
        let cleanUnit = unit.trimmingCharacters(in: .whitespacesAndNewlines)

        let nextOrder = (dashboard.widgets.map(\.order).max() ?? -1) + 1
        let pin = Int(pinText.trimmingCharacters(in: .whitespacesAndNewlines)) // nil wenn leer/ungültig

        // Neue Felder konvertieren
        let step = Double(stepText.trimmingCharacters(in: .whitespacesAndNewlines))
        let maxHistoryPoints = Int(maxHistoryPointsText.trimmingCharacters(in: .whitespacesAndNewlines))
        let format = formatText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : formatText.trimmingCharacters(in: .whitespacesAndNewlines)
        let refreshInterval = Int(refreshIntervalText.trimmingCharacters(in: .whitespacesAndNewlines))
        let debounceMs = Int(debounceMsText.trimmingCharacters(in: .whitespacesAndNewlines))
        let optionsCSV = optionsText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : optionsText.trimmingCharacters(in: .whitespacesAndNewlines)

        let widget = Widget(
            title: cleanTitle,
            value: initial,
            minValue: min,
            maxValue: max,
            unit: cleanUnit,
            kind: selectedKind,
            topic: finalTopic,
            order: nextOrder,
            pin: pin,
            step: step,
            maxHistoryPoints: maxHistoryPoints,
            format: format,
            refreshInterval: refreshInterval,
            debounceMs: debounceMs,
            invert: invert,
            optionsCSV: optionsCSV
        )

        dashboard.widgets.append(widget)
        dashboard.updatedAt = Date()

        try? modelContext.save()
        dismiss()
    }
}

// MARK: - WidgetKind Erweiterung

extension WidgetKind {
    // Welche WidgetKinds gelten als Outputs (schaltbar / stellbar)
    var isOutput: Bool {
        switch self {
        case .toggle, .switcher, .button, .slider, .servo, .rgb:
            return true
        default:
            return false
        }
    }

    var isInput: Bool {
        switch self {
        case .sensorAnalog, .sensorBinary, .chart, .camera, .value:
            return true
        default:
            return !isOutput
        }
    }

    // Numerische Widgets (zeigen / messen numerische Werte)
    var isNumeric: Bool {
        switch self {
        case .gauge, .value, .slider, .servo, .progress, .sensorAnalog:
            return true
        default:
            return false
        }
    }
}
