//
//  DashboardDetailView.swift
//  MC Connect
//
//  Created by Martin Lanius on 24.10.25.
//

import SwiftUI
import SwiftData

struct DashboardDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var mqtt: MqttViewModel

    @Bindable var dashboard: Dashboard
    init(dashboard: Dashboard) {
        self._dashboard = Bindable(wrappedValue: dashboard)
    }

    @State private var showingAddWidget = false

    private var columns: [GridItem] = [
        GridItem(.adaptive(minimum: 150), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(sortedWidgets) { w in
                    WidgetCard(
                        widget: w,
                        dashboard: dashboard,
                        onToggle: { newState in
                            // Nur senden, wenn verbunden
                            guard mqtt.isConnected else {
                                print("WARN: MQTT nicht verbunden")
                                return
                            }

                            // Befehl analog DevicesView senden
                            if let pin = w.pin {
                                // Externer GPIO (z. B. LED/Relais)
                                let payload: [String: Any] = [
                                    "target": "gpio",
                                    "value": newState ? 1 : 0,
                                    "pin": pin
                                ]
                                mqtt.publish(topic: w.topic ?? "pi/cmd", json: payload)
                                print("MQTT publish gpio ->", payload)
                            } else {
                                // Onboard-LED Test
                                let payload: [String: Any] = [
                                    "target": "led",
                                    "value": newState ? 1 : 0
                                ]
                                mqtt.publish(topic: w.topic ?? "pi/cmd", json: payload)
                                print("MQTT publish led ->", payload)
                            }

                            // UI/Model aktualisieren
                            w.value = newState ? 1 : 0
                            dashboard.updatedAt = Date()
                            try? modelContext.save()
                        }
                    )
                    .environmentObject(mqtt) // wichtig, damit WidgetCard direkten Zugriff auf mqtt hat
                }
            }
            .padding()
        }
        .navigationTitle(dashboard.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button { showingAddWidget = true } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showingAddWidget) {
            WidgetInputView(dashboard: dashboard)
                .presentationDetents([.medium, .large])
        }
    }

    private var sortedWidgets: [Widget] {
        dashboard.widgets.sorted(by: { $0.order < $1.order })
    }
}

private struct WidgetCard: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var mqtt: MqttViewModel

    @Bindable var widget: Widget
    @Bindable var dashboard: Dashboard
    var onToggle: ((Bool) -> Void)?

    @State private var showEdit = false
    @State private var showDeleteConfirm = false

    // Local states for interactive widgets
    @State private var sliderValue: Double = 0
    @State private var pickerSelection: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(widget.title)
                .font(.headline)

            // Hinweis anzeigen, falls Toggle ohne sendbaren Kontext
            if widget.kind == .toggle {
                // Optionaler Hinweis, wenn keine Verbindung: wird in Parent geprüft
            }

            // Render different widget UIs depending on kind
            switch widget.kind {
            case .value:
                ValueWidget(value: widget.value, unit: widget.unit)

            case .gauge:
                GaugeWidget(value: widget.value, min: widget.minValue, max: widget.maxValue, unit: widget.unit)

            case .progress:
                ProgressWidget(value: widget.value, min: widget.minValue, max: widget.maxValue, unit: widget.unit)

            case .toggle, .switcher:
                ToggleWidget(isOn: widget.value >= 0.5, unit: widget.unit, onToggle: { newState in
                    // prefer parent onToggle if provided
                    if let onToggle = onToggle {
                        onToggle(newState)
                    } else {
                        // local publish
                        publishBinaryChange(to: newState)
                    }
                    widget.value = newState ? 1 : 0
                    dashboard.updatedAt = Date()
                    try? modelContext.save()
                })

            case .button:
                GenericWidgetView(widget: widget, actionTitle: "Trigger") {
                    publishMomentary()
                }

            case .slider:
                VStack(alignment: .leading) {
                    HStack {
                        Text(formatted(widget.value))
                            .font(.subheadline.monospacedDigit())
                        Spacer()
                    }
                    HStack {
                        Slider(value: Binding(get: {
                            widget.value
                        }, set: { new in
                            widget.value = new
                        }), in: widget.minValue...widget.maxValue, step: widget.step ?? 1)
                        .onAppear {
                            sliderValue = widget.value
                        }
                    }
                    HStack {
                        Button("Set") {
                            publishNumericValue(widget.value)
                            dashboard.updatedAt = Date()
                            try? modelContext.save()
                        }
                        .buttonStyle(.borderedProminent)
                        Spacer()
                    }
                }

            case .sensorAnalog:
                // Read-only numeric sensor — show as gauge if range is meaningful
                if widget.maxValue > widget.minValue {
                    GaugeWidget(value: widget.value, min: widget.minValue, max: widget.maxValue, unit: widget.unit)
                } else {
                    ValueWidget(value: widget.value, unit: widget.unit)
                }

            case .sensorBinary:
                ValueWidget(value: widget.value, unit: widget.unit)

            case .picker:
                if let options = widget.options, !options.isEmpty {
                    PickerWidget(options: options, selected: options.first ?? "") { selected in
                        // publish selection
                        publishSelection(selected)
                        widget.options = widget.options // keep
                        dashboard.updatedAt = Date()
                        try? modelContext.save()
                    }
                } else {
                    GenericWidgetView(widget: widget, actionTitle: "Select") { }
                }

            case .chart:
                ChartPlaceholderView(title: widget.title, latestValue: widget.value)

            case .text:
                GenericWidgetView(widget: widget, actionTitle: "")

            case .rgb:
                GenericWidgetView(widget: widget, actionTitle: "Set Color") {
                    // For now: publish a placeholder RGB payload (user can adapt)
                    let payload: [String: Any] = [
                        "target": "rgb",
                        "value": ["r": 255, "g": 128, "b": 0],
                        "pin": widget.pin as Any
                    ]
                    mqtt.publish(topic: widget.topic ?? "pi/cmd", json: payload)
                }

            case .servo:
                VStack(alignment: .leading) {
                    HStack {
                        Text("Pos: \(Int(widget.value))°")
                        Spacer()
                    }
                    Slider(value: Binding(get: { widget.value }, set: { widget.value = $0 }), in: widget.minValue...widget.maxValue, step: widget.step ?? 1)
                    Button("Set Position") {
                        publishNumericValue(widget.value)
                        dashboard.updatedAt = Date()
                        try? modelContext.save()
                    }
                    .buttonStyle(.borderedProminent)
                }

            case .camera:
                ChartPlaceholderView(title: widget.title, latestValue: widget.value) // placeholder

            default:
                // Fallback
                GenericWidgetView(widget: widget, actionTitle: widget.kind.isOutput ? "Act" : "") { }
            }
        }
        .padding()
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.08)))
        .contextMenu {
            Button {
                showEdit = true
            } label: {
                Label("Bearbeiten", systemImage: "pencil")
            }
            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
        .onTapGesture { showEdit = true }
        .sheet(isPresented: $showEdit) {
            ChangeWidgetView(widget: widget, dashboard: dashboard)
                .environmentObject(mqtt)
        }
        .alert("Widget löschen?", isPresented: $showDeleteConfirm) {
            Button("Abbrechen", role: .cancel) {}
            Button("Löschen", role: .destructive) { deleteWidget() }
        } message: {
            Text("Dieses Widget wird aus dem Dashboard entfernt.")
        }
    }

    // MARK: - Actions / Publishes

    private func publishBinaryChange(to newState: Bool) {
        guard mqtt.isConnected else { return }
        let topic = widget.topic ?? "pi/cmd"
        if let pin = widget.pin {
            let payload: [String: Any] = ["target": "gpio", "pin": pin, "value": newState ? 1 : 0]
            mqtt.publish(topic: topic, json: payload)
        } else {
            let payload: [String: Any] = ["target": "led", "value": newState ? 1 : 0]
            mqtt.publish(topic: topic, json: payload)
        }
    }

    private func publishMomentary() {
        guard mqtt.isConnected else { return }
        let topic = widget.topic ?? "pi/cmd"
        var payload: [String: Any] = ["target": "button", "value": 1]
        if let pin = widget.pin { payload["pin"] = pin }
        mqtt.publish(topic: topic, json: payload)
    }

    private func publishNumericValue(_ value: Double) {
        guard mqtt.isConnected else { return }
        let topic = widget.topic ?? "pi/cmd"
        var payload: [String: Any] = ["target": "value", "value": value]
        if let pin = widget.pin { payload["pin"] = pin }
        mqtt.publish(topic: topic, json: payload)
    }

    private func publishSelection(_ selection: String) {
        guard mqtt.isConnected else { return }
        let topic = widget.topic ?? "pi/cmd"
        var payload: [String: Any] = ["target": "select", "value": selection]
        if let pin = widget.pin { payload["pin"] = pin }
        mqtt.publish(topic: topic, json: payload)
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
    }
}

private struct ValueWidget: View {
    let value: Double
    let unit: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text(formatted(value))
                .font(.system(size: 28, weight: .bold, design: .rounded))
            if !unit.isEmpty {
                Text(unit)
                    .foregroundColor(.secondary)
            }
        }
    }
}

private struct ProgressWidget: View {
    let value: Double
    let min: Double
    let max: Double
    let unit: String

    var progress: Double {
        guard max > min else { return 0 }
        let clamped = Swift.min(Swift.max(value, min), max)
        return (clamped - min) / (max - min)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ProgressView(value: progress)
            HStack {
                Text(formatted(value))
                if !unit.isEmpty { Text(unit).foregroundColor(.secondary) }
                Spacer()
                Text("\(Int(progress * 100))%").foregroundColor(.secondary)
            }
            .font(.footnote)
        }
    }
}

private struct GaugeWidget: View {
    let value: Double
    let min: Double
    let max: Double
    let unit: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            let progress = Swift.max(0, Swift.min(1, (value - min) / Swift.max(max - min, 0.0001)))
            ZStack(alignment: .leading) {
                Capsule().fill(Color.gray.opacity(0.2)).frame(height: 12)
                GeometryReader { geo in
                    Capsule().fill(Color.accentColor)
                        .frame(width: geo.size.width * progress, height: 12)
                }
            }
            .frame(height: 12)
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(formatted(value)).font(.system(size: 24, weight: .semibold, design: .rounded))
                if !unit.isEmpty { Text(unit).foregroundColor(.secondary) }
                Spacer()
                Text("min \(formatted(min)) / max \(formatted(max))")
                    .foregroundColor(.secondary)
                    .font(.footnote)
            }
        }
    }
}

private struct ToggleWidget: View {
    @State var isOn: Bool
    let unit: String
    var onToggle: ((Bool) -> Void)?

    var body: some View {
        HStack {
            Text(isOn ? "ON" : "OFF")
                .font(.system(size: 20, weight: .semibold))
                .foregroundColor(isOn ? .blue : .secondary)
            Spacer()
            Button(isOn ? "Ausschalten" : "Einschalten") {
                isOn.toggle()
                onToggle?(isOn)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
        }
    }
}

// MARK: - Helpers / Placeholders

private struct GenericWidgetView: View {
    let widget: Widget
    var actionTitle: String = ""
    var action: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(widget.title)
                    .font(.headline)
                Spacer()
                Text(String(format: widget.format ?? "%.2f", widget.value))
                    .font(.subheadline.monospacedDigit())
            }
            if !widget.unit.isEmpty {
                Text(widget.unit).font(.caption).foregroundColor(.secondary)
            }
            if !actionTitle.isEmpty {
                Button(actionTitle) {
                    action?()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct ChartPlaceholderView: View {
    let title: String
    let latestValue: Double

    var body: some View {
        VStack(alignment: .leading) {
            Text(title).font(.headline)
            Text("Latest: \(formatted(latestValue))").font(.subheadline)
            Rectangle()
                .fill(Color.secondary.opacity(0.12))
                .frame(height: 72)
                .overlay(Text("Chart placeholder").foregroundColor(.secondary))
        }
        .padding(.vertical, 6)
    }
}

private struct PickerWidget: View {
    let options: [String]
    @State private var selected: String
    var onSelect: (String) -> Void

    init(options: [String], selected: String, onSelect: @escaping (String) -> Void) {
        self.options = options
        self._selected = State(initialValue: selected)
        self.onSelect = onSelect
    }

    var body: some View {
        Picker(selection: $selected, label: Text("Auswahl")) {
            ForEach(options, id: \.self) { opt in
                Text(opt).tag(opt)
            }
        }
        .pickerStyle(.menu)
        .onChange(of: selected) { _, new in onSelect(new) }
    }
}

private func formatted(_ value: Double) -> String {
    let formatter = NumberFormatter()
    formatter.numberStyle = .decimal
    formatter.maximumFractionDigits = 1
    return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
}
