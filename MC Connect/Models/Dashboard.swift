//
//  Dashboard.swift
//  MC Connect
//
//  Created by Martin Lanius on 24.10.25.
//

import Foundation
import SwiftData

enum WidgetKind: String, Codable, CaseIterable, Identifiable {
    case gauge, value, toggle, switcher, button, slider, progress
    case sensorBinary, sensorAnalog, chart, text, rgb, servo, picker, camera
    var id: String { rawValue }
}

@Model
final class Dashboard: Identifiable {
    @Attribute(.unique) var id: UUID = UUID()
    var name: String
    var info: String?
    var deviceId: String

    var createdAt: Date = Date()
    var updatedAt: Date = Date()

    @Relationship(deleteRule: .cascade) var widgets: [Widget] = []

    init(name: String, info: String? = nil, deviceId: String = "") {
        self.name = name
        self.info = info
        self.deviceId = deviceId
    }
}
