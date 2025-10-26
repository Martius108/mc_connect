//
//  Dashboard.swift
//  MC Connect
//
//  Created by Martin Lanius on 24.10.25.
//

import Foundation
import SwiftData

enum WidgetKind: String, Codable, CaseIterable, Identifiable {
    case gauge
    case value
    case toggle        // einfacher on/off toggle
    case switcher      // klarer Zustandsschalter (on/off)
    case button        // momentary (push)
    case slider        // stufenloser Wert (z.B. PWM)
    case progress
    case sensorBinary  // z.B. PIR, Reed (0/1)
    case sensorAnalog  // z.B. Abstand, Temperatur (numerisch)
    case chart         // Zeitverlauf
    case text          // Status / Log / Freitext
    case rgb           // RGB-LED (hex oder r,g,b)
    case servo         // Servo-Position (0-180)
    case picker        // Auswahl aus Optionen
    case camera        // Bild-Widget
    // später: chartMulti, map, custom
    var id: String { rawValue }
}

@Model
final class Widget {
    @Attribute(.unique) var id: UUID

    // Basisfelder
    var title: String
    var value: Double
    var minValue: Double
    var maxValue: Double
    var unit: String
    var kindRaw: String // SwiftData speichert Enums als String
    var topic: String?
    var order: Int
    var pin: Int?

    // Erweiterte optionale Felder für verschiedene WidgetKinds
    // Für slider / servo / rgb / etc.
    var step: Double?                // z.B. Schrittweite für Slider
    var maxHistoryPoints: Int?       // für chart: wie viele Punkte behalten
    var format: String?              // z.B. "%.1f °C" für Anzeigeformat

    // Für sensor widgets / chart
    var refreshInterval: Int?        // in Sekunden, Polling / Aggregation
    var debounceMs: Int?             // Entprellung für digitale Sensoren

    // Für invertierte Logik (z.B. active-low)
    var invert: Bool = false

    // Options für Picker / Auswahl-Widgets — als CSV gespeichert (robust für SwiftData)
    // z.B. "auto,manual,off"
    var optionsCSV: String?

    // Beziehung
    @Relationship(inverse: \Dashboard.widgets) var dashboard: Dashboard?

    // Computed: Enum-Zugriff
    var kind: WidgetKind {
        get { WidgetKind(rawValue: kindRaw) ?? .value }
        set { kindRaw = newValue.rawValue }
    }

    // Computed: Optionen als Array
    var options: [String]? {
        get {
            guard let csv = optionsCSV?.trimmingCharacters(in: .whitespacesAndNewlines), !csv.isEmpty else { return nil }
            return csv.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        set {
            if let arr = newValue, !arr.isEmpty {
                optionsCSV = arr.joined(separator: ",")
            } else {
                optionsCSV = nil
            }
        }
    }

    init(
        id: UUID = UUID(),
        title: String,
        value: Double = 0,
        minValue: Double = 0,
        maxValue: Double = 100,
        unit: String = "",
        kind: WidgetKind,
        topic: String? = nil,
        order: Int = 0,
        pin: Int? = nil,
        // Neue optionale Parameter mit sinnvollen Defaults
        step: Double? = nil,
        maxHistoryPoints: Int? = nil,
        format: String? = nil,
        refreshInterval: Int? = nil,
        debounceMs: Int? = nil,
        invert: Bool = false,
        optionsCSV: String? = nil
    ) {
        self.id = id
        self.title = title
        self.value = value
        self.minValue = minValue
        self.maxValue = maxValue
        self.unit = unit
        self.kindRaw = kind.rawValue
        self.topic = topic
        self.order = order
        self.pin = pin

        // neue Felder
        self.step = step
        self.maxHistoryPoints = maxHistoryPoints
        self.format = format
        self.refreshInterval = refreshInterval
        self.debounceMs = debounceMs
        self.invert = invert
        self.optionsCSV = optionsCSV
    }
}

@Model
final class Dashboard {
    @Attribute(.unique) var id: UUID
    var name: String
    var info: String?
    var deviceId: String?
    var createdAt: Date
    var updatedAt: Date

    @Relationship(deleteRule: .cascade) var widgets: [Widget] = []

    init(
        id: UUID = UUID(),
        name: String,
        info: String? = nil
    ) {
        self.id = id
        self.name = name
        self.info = info
        self.createdAt = Date()
        self.updatedAt = Date()
    }
}
