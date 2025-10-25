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
    case toggle
    case progress
    // später: chart, switch, etc.

    var id: String { rawValue }
}

@Model
final class Widget {
    @Attribute(.unique) var id: UUID
    var title: String
    var value: Double
    var minValue: Double
    var maxValue: Double
    var unit: String
    var kindRaw: String // SwiftData speichert Enums als String
    var topic: String?
    var order: Int
    var pin: Int?

    @Relationship(inverse: \Dashboard.widgets) var dashboard: Dashboard?

    var kind: WidgetKind {
        get { WidgetKind(rawValue: kindRaw) ?? .value }
        set { kindRaw = newValue.rawValue }
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
        pin: Int? = nil
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
    }
}

@Model
final class Dashboard {
    @Attribute(.unique) var id: UUID
    var name: String
    var info: String?
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
