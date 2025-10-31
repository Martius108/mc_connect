//
//  DashboardHelper.swift
//  MC Connect
//
//  Created by Martin Lanius on 30.10.25.
//

import SwiftUI
import SwiftData

// MARK: - Extension with helpers
extension DashboardDetailView {
    // sortedWidgets used by the view body
    var sortedWidgets: [Widget] {
        let widgets = dashboard.widgets.sorted(by: { $0.order < $1.order })
        print("[DashboardDetailView] sortedWidgets count: \(widgets.count)")
        return widgets
    }

    // Connection badge uses dashboard.deviceId (externalId)
    var connectionBadge: some View {
        HStack(spacing: 8) {
            Group {
                let effectiveId = dashboard.deviceId

                if mqtt.isConnected && mqtt.connectedDeviceId == effectiveId {
                    Circle().foregroundColor(.green).frame(width: 10, height: 10)
                } else if connecting {
                    ProgressView().scaleEffect(0.5)
                } else {
                    Circle().foregroundColor(.red).frame(width: 10, height: 10)
                }
            }
            .accessibilityHidden(true)

            Button(action: {
                Task {
                    let effectiveId = dashboard.deviceId

                    if mqtt.isConnected && mqtt.connectedDeviceId == effectiveId {
                        stopMqttIfOwned()
                    } else {
                        await startMqttForDashboard(forceReconnect: true)
                    }
                }
            }) {
                let effectiveId = dashboard.deviceId
                Text(mqtt.isConnected && mqtt.connectedDeviceId == effectiveId ? "Disconnect" : "Connect")
                    .font(.subheadline)
            }
        }
    }

    // MARK: - MQTT start / stop
    @MainActor
    func startMqttForDashboard(forceReconnect: Bool = false) async {
        print("[Dashboard] startMqttForDashboard(forceReconnect: \(forceReconnect))")
        let dashDeviceId = dashboard.deviceId // now non-optional and contains externalId

        // Debug: list available devices (optional)
        do {
            let allDevices = try modelContext.fetch(FetchDescriptor<Device>())
            print("[Dashboard] Available devices in modelContext:")
            for device in allDevices {
                print("  - id: \(device.id), externalId: \(device.externalId), name: \(device.name), clientID: \(device.clientID)")
            }
        } catch {
            print("[Dashboard] Fehler beim Laden der Devices: \(error)")
        }

        if !forceReconnect, mqtt.isConnected, mqtt.connectedDeviceId == dashDeviceId {
            print("[Dashboard] bereits verbunden mit device \(dashDeviceId)")
            return
        }

        do {
            // Find device by externalId (since dashboard.deviceId is externalId)
            let devices = try modelContext.fetch(FetchDescriptor<Device>())
            guard let device = devices.first(where: { $0.externalId == dashDeviceId }) else {
                print("[Dashboard] Device mit externalId '\(dashDeviceId)' nicht gefunden")
                return
            }

            print("[Dashboard] Found device for connection: id=\(device.id), externalId=\(device.externalId), name=\(device.name), clientID=\(device.clientID)")
            localDevice = device
            connecting = true
            lastConnectError = nil

            mqtt.setConfig(
                host: device.host,
                port: device.port,
                clientID: device.clientID,
                username: device.username,
                password: device.password
            )

            // effectiveDeviceId is the externalId (dashboard.deviceId)
            let effectiveDeviceId = dashDeviceId

            let topicsToSubscribe = [
                "device/\(effectiveDeviceId)/telemetry/#",
                "device/\(effectiveDeviceId)/status",
                "device/\(effectiveDeviceId)/ack"
            ]
            print("[Dashboard] Connecting with topicsToSubscribe: \(topicsToSubscribe)")

            // Call connect for the specific device externalId.
            // The MqttViewModel / MqttService manages subscriptions based on the provided device id.
            mqtt.connect(for: effectiveDeviceId, subscribeTo: topicsToSubscribe)

            let timeoutNanos: UInt64 = 2_500 * 1_000_000
            let pollIntervalNanos: UInt64 = 200 * 1_000_000
            var waited: UInt64 = 0
            while !mqtt.isConnected && waited < timeoutNanos {
                try await Task.sleep(nanoseconds: pollIntervalNanos)
                waited += pollIntervalNanos
            }

            if mqtt.isConnected {
                print("[Dashboard] MQTT verbunden für device (externalId) \(dashDeviceId) (effectiveId=\(effectiveDeviceId))")
            } else {
                lastConnectError = "Verbindung nicht hergestellt"
                print("[Dashboard] MQTT konnte nicht verbunden werden für device \(dashDeviceId)")
            }
        } catch {
            lastConnectError = "Fetch Device failed: \(error.localizedDescription)"
            print("[Dashboard] Fehler beim Laden desDevices: \(error)")
        }
        connecting = false
    }

    @MainActor
    func stopMqttIfOwned() {
        guard localDevice != nil else { return }
        mqtt.disconnect()
        print("[Dashboard] MQTT disconnected for device externalId=\(dashboard.deviceId)")
        localDevice = nil
    }

    // NOTE:
    // The functions below were intentionally renamed to avoid name collisions
    // with WidgetCard's internal helper methods. They can still be used from
    // other parts of DashboardDetailView if needed.

    func dashboardPublishBinaryChange(dashboard: Dashboard, widget: Widget, to newState: Bool) {
        guard mqtt.isConnected else { return }
        let topic = "device/\(dashboard.deviceId)/command"
        if let pin = widget.pin {
            let payload: [String: Any] = ["target": "gpio", "pin": pin, "value": newState ? 1 : 0]
            mqtt.publish(topic: topic, json: payload)
        } else {
            let payload: [String: Any] = ["target": "led", "value": newState ? 1 : 0]
            mqtt.publish(topic: topic, json: payload)
        }
    }

    func dashboardPublishMomentary(dashboard: Dashboard, widget: Widget) {
        guard mqtt.isConnected else { return }
        let topic = "device/\(dashboard.deviceId)/command"
        var payload: [String: Any] = ["target": "button", "value": 1]
        if let pin = widget.pin { payload["pin"] = pin }
        mqtt.publish(topic: topic, json: payload)
    }

    func dashboardPublishNumericValue(dashboard: Dashboard, widget: Widget, value: Double) {
        guard mqtt.isConnected else { return }
        let topic = "device/\(dashboard.deviceId)/command"
        var payload: [String: Any] = ["target": "value", "value": value]
        if let pin = widget.pin { payload["pin"] = pin }
        mqtt.publish(topic: topic, json: payload)
    }

    func dashboardPublishSelection(dashboard: Dashboard, widget: Widget, selection: String) {
        guard mqtt.isConnected else { return }
        let topic = "device/\(dashboard.deviceId)/command"
        var payload: [String: Any] = ["target": "select", "value": selection]
        if let pin = widget.pin { payload["pin"] = pin }
        mqtt.publish(topic: topic, json: payload)
    }

    // --- Minimal compatibility wrappers so old calls still resolve ---
    func publishBinaryChange(for dashboard: Dashboard, widget: Widget, to newState: Bool) {
        dashboardPublishBinaryChange(dashboard: dashboard, widget: widget, to: newState)
    }

    func publishMomentary(for dashboard: Dashboard, widget: Widget) {
        dashboardPublishMomentary(dashboard: dashboard, widget: widget)
    }

    func publishNumericValue(for dashboard: Dashboard, widget: Widget, value: Double) {
        dashboardPublishNumericValue(dashboard: dashboard, widget: widget, value: value)
    }

    func publishSelection(for dashboard: Dashboard, widget: Widget, selection: String) {
        dashboardPublishSelection(dashboard: dashboard, widget: widget, selection: selection)
    }
}

// MARK: - WidgetCard + Telemetry Handling + UI helpers
struct WidgetCard: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject var mqtt: MqttViewModel

    @Bindable var widget: Widget
    @Bindable var dashboard: Dashboard
    var onToggle: ((Bool) -> Void)?

    @State private var showEdit = false
    @State private var showDeleteConfirm = false

    @State private var sliderValue: Double = 0
    @State private var pickerSelection: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(widget.title)
                .font(.headline)

            switch widget.kind {
            case .value:
                ValueWidget(value: widget.value, unit: widget.unit)

            case .gauge:
                GaugeWidget(value: widget.value, min: widget.minValue, max: widget.maxValue, unit: widget.unit)

            case .progress:
                ProgressWidget(value: widget.value, min: widget.minValue, max: widget.maxValue, unit: widget.unit)

            case .toggle, .switcher:
                ToggleWidget(isOn: widget.value >= 0.5, unit: widget.unit, onToggle: { newState in
                    if let onToggle = onToggle {
                        onToggle(newState)
                    } else {
                        // Default: use WidgetCard's local publishing
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
                        publishSelection(selected)
                        widget.options = widget.options
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
                    let payload: [String: Any] = [
                        "target": "rgb",
                        "value": ["r": 255, "g": 128, "b": 0],
                        "pin": widget.pin as Any
                    ]
                    mqtt.publish(topic: "device/\(dashboard.deviceId)/command", json: payload)
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
                ChartPlaceholderView(title: widget.title, latestValue: widget.value)

            default:
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
        .onReceive(NotificationCenter.default.publisher(for: .mqttTelemetryReceived)) { note in
            guard let info = note.userInfo else { return }
            Task { @MainActor in
                handleTelemetryNotification(info)
            }
        }
        .onAppear {
            print("[WidgetCard] onAppear - widget.id=\(widget.id) widget.title=\(widget.title) widget.topicSuffix=\(String(describing: widget.topicSuffix))")
        }
    }

    // MARK: - WidgetCard-local publishing helper wrappers (avoid name collisions)
    private func publishBinaryChange(to newState: Bool) {
        guard mqtt.isConnected else { return }
        let topic = "device/\(dashboard.deviceId)/command"
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
        let topic = "device/\(dashboard.deviceId)/command"
        var payload: [String: Any] = ["target": "button", "value": 1]
        if let pin = widget.pin { payload["pin"] = pin }
        mqtt.publish(topic: topic, json: payload)
    }

    private func publishNumericValue(_ value: Double) {
        guard mqtt.isConnected else { return }
        let topic = "device/\(dashboard.deviceId)/command"
        var payload: [String: Any] = ["target": "value", "value": value]
        if let pin = widget.pin { payload["pin"] = pin }
        mqtt.publish(topic: topic, json: payload)
    }

    private func publishSelection(_ selection: String) {
        guard mqtt.isConnected else { return }
        let topic = "device/\(dashboard.deviceId)/command"
        var payload: [String: Any] = ["target": "select", "value": selection]
        if let pin = widget.pin { payload["pin"] = pin }
        mqtt.publish(topic: topic, json: payload)
    }

    private func deleteWidget() {
        if let idx = dashboard.widgets.firstIndex(where: { $0.id == widget.id }) {
            dashboard.widgets.remove(at: idx)
        }
        for (i, w) in dashboard.widgets.enumerated() { w.order = i }
        dashboard.updatedAt = Date()
        modelContext.delete(widget)
        try? modelContext.save()
    }

    // Telemetry handling - rely on Notification's userInfo keys
    @MainActor
    private func handleTelemetryNotification(_ info: [AnyHashable: Any]) {
        guard let topic = info["topic"] as? String else { return }

        // Extract reported/topic device IDs from notification (MqttService liefert diese keys)
        var reportedDeviceId: String? = nil
        if let rep = info["reportedDeviceId"] as? String, !rep.isEmpty {
            reportedDeviceId = rep
        }
        var topicDeviceId: String? = nil
        if let top = info["topicDeviceId"] as? String, !top.isEmpty {
            topicDeviceId = top
        }

        // Find the Device corresponding to this dashboard by externalId
        var deviceForDashboard: Device? = nil
        if let devices = try? modelContext.fetch(FetchDescriptor<Device>()) {
            deviceForDashboard = devices.first(where: { $0.externalId == dashboard.deviceId })
        }

        // If device exists and has no externalId, and we received a reportedDeviceId, set and persist it
        if let dev = deviceForDashboard {
            if dev.externalId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let rep = reportedDeviceId {
                dev.externalId = rep
                dashboard.updatedAt = Date()
                do {
                    try modelContext.save()
                    print("[Dashboard] device.externalId set to '\(rep)' for device.id=\(dev.id)")
                } catch {
                    print("[Dashboard] Failed to save externalId for device.id=\(dev.id): \(error)")
                }
            }
        }

        // Determine whether this incoming message actually belongs to this dashboard/device.
        var belongsToThisDevice = false

        // If reportedDeviceId is present and matches dashboard.deviceId (externalId), accept
        if let rep = reportedDeviceId, rep == dashboard.deviceId {
            belongsToThisDevice = true
        }

        // If topicDeviceId is present and matches dashboard.deviceId (externalId), accept
        if !belongsToThisDevice, let top = topicDeviceId, top == dashboard.deviceId {
            belongsToThisDevice = true
        }

        // If we have a device record and its externalId matches dashboard.deviceId, that's also ok
        if !belongsToThisDevice, let dev = deviceForDashboard {
            if dev.externalId == dashboard.deviceId {
                belongsToThisDevice = true
            }
        }

        // Fallback: if dashboard.deviceId matches a topic segment (e.g. device/<id>/telemetry)
        if !belongsToThisDevice {
            let parts = topic.split(separator: "/")
            if parts.count >= 2 {
                let maybeId = String(parts[1])
                if maybeId == dashboard.deviceId {
                    belongsToThisDevice = true
                }
            }
        }

        if !belongsToThisDevice {
            print("[WidgetCard] Ignoring telemetry for topic=\(topic) — not matching device (reportedDeviceId=\(reportedDeviceId ?? "nil") topicDeviceId=\(topicDeviceId ?? "nil"))")
            return
        }

        // Topic: device/esp01/telemetry/temperature  (oder device/<id>/telemetry)
        let parts = topic.split(separator: "/")
        // suffix optional — if a fourth segment exists, that is e.g. "temperature"
        let suffix: String? = parts.count >= 4 ? String(parts[3]) : nil

        // If suffix exists, match by it
        if let suffix = suffix {
            if widget.topicSuffix == suffix {
                if let value = extractNumericValue(from: info) {
                    updateWidgetValueIfNeeded(value)
                }
            }
            return
        }

        // No suffix in topic (e.g. "device/<id>/telemetry"), try keys in raw JSON
        if let raw = info["raw"] as? [String: Any] {
            if let widgetSuffix = widget.topicSuffix {
                if raw.keys.contains(widgetSuffix) {
                    if let value = extractNumericValue(from: info) {
                        updateWidgetValueIfNeeded(value)
                    }
                }
            } else {
                // If widget has no topicSuffix, fallback to the raw value or value key
                if let value = extractNumericValue(from: info) {
                    updateWidgetValueIfNeeded(value)
                }
            }
        } else {
            // No raw JSON — as last resort try payload-as-number
            if let value = extractNumericValue(from: info) {
                updateWidgetValueIfNeeded(value)
            }
        }
    }

    private func extractNumericValue(from info: [AnyHashable: Any]) -> Double? {
        if let v = info["value"] as? Double { return v }
        if let n = info["value"] as? NSNumber { return n.doubleValue }
        if let i = info["value"] as? Int { return Double(i) }
        if let s = info["value"] as? String, let d = Double(s) { return d }

        if let raw = info["raw"] as? [String: Any] {
            if let v = raw["value"] as? Double { return v }
            if let n = raw["value"] as? NSNumber { return n.doubleValue }
            if let i = raw["value"] as? Int { return Double(i) }
            if let s = raw["value"] as? String, let d = Double(s) { return d }

            if let obstacle = raw["obstacle"] as? Bool { return obstacle ? 1.0 : 0.0 }
            if let temp = raw["temperature"] as? Double { return temp }
            if let tempStr = raw["temperature"] as? String, let d = Double(tempStr) { return d }
            if let hum = raw["humidity"] as? Double { return hum }
            if let humStr = raw["humidity"] as? String, let d = Double(humStr) { return d }
        }

        return nil
    }

    private func updateWidgetValueIfNeeded(_ newVal: Double) {
        print("[Widget] updateWidgetValueIfNeeded for widget=\(widget.id) old=\(widget.value) new=\(newVal)")
        if widget.value == newVal {
            print("[Widget] values equal -- skipping update")
            return
        }
        widget.value = newVal
        dashboard.updatedAt = Date()
        do {
            try modelContext.save()
            print("[Widget] widget value updated and saved")
        } catch {
            print("[Widget] save failed: \(error)")
        }
    }
}

// MARK: - UI Helper Views

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

// MARK: - Notification Names for Widget actions (optional pattern)
extension Notification.Name {
    static let widgetPublishBinaryChange = Notification.Name("widgetPublishBinaryChange")
    static let widgetPublishMomentary = Notification.Name("widgetPublishMomentary")
    static let widgetPublishNumericValue = Notification.Name("widgetPublishNumericValue")
    static let widgetPublishSelection = Notification.Name("widgetPublishSelection")
}
