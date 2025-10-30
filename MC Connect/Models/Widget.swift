//
//  Widget.swift
//  MC Connect
//
//  Created by Martin Lanius on 29.10.25.
//

import Foundation
import SwiftData

@Model
final class Widget {
    @Attribute(.unique) var id: UUID = UUID()

    // Basisfelder
    var title: String
    var value: Double
    var minValue: Double
    var maxValue: Double
    var unit: String

    // Enum stored as raw string for SwiftData
    var kindRaw: String

    // MQTT / Topic
    var topic: String?

    // Ordering, hardware pin
    var order: Int
    var pin: Int?

    // Erweiterte optionale Felder
    var step: Double?                // z.B. Schrittweite für Slider
    var maxHistoryPoints: Int?       // für chart: wie viele Punkte behalten
    var format: String?              // z.B. "%.1f °C" für Anzeigeformat
    var refreshInterval: Int?        // in Sekunden, Polling / Aggregation
    var debounceMs: Int?             // Entprellung für digitale Sensoren
    var invert: Bool = false         // active-low
    var optionsCSV: String?          // CSV für Picker-Optionen

    // Timestamps (optional, hilfreich)
    var createdAt: Date
    var updatedAt: Date

    // Beziehung: Dashboard (inverse relationship referenziert Dashboard.widgets)
    @Relationship(inverse: \Dashboard.widgets) var dashboard: Dashboard?

    // Computed: Enum-Zugriff
    var kind: WidgetKind {
        get { WidgetKind(rawValue: kindRaw) ?? .value }
        set { kindRaw = newValue.rawValue }
    }

    // Computed helper: options als Array
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

    // Computed helper: topic suffix (z. B. "temperature" aus "device/esp01/telemetry/temperature")
    var topicSuffix: String? {
        guard let t = topic?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
        let parts = t.split(separator: "/").map { String($0) }
        return parts.last
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
        step: Double? = nil,
        maxHistoryPoints: Int? = nil,
        format: String? = nil,
        refreshInterval: Int? = nil,
        debounceMs: Int? = nil,
        invert: Bool = false,
        optionsCSV: String? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
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

        self.step = step
        self.maxHistoryPoints = maxHistoryPoints
        self.format = format
        self.refreshInterval = refreshInterval
        self.debounceMs = debounceMs
        self.invert = invert
        self.optionsCSV = optionsCSV

        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}
