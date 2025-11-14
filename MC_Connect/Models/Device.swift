//
//  Device.swift
//  MC_Connect
//
//  Created by Martin Lanius on 09.11.25.
//

import Foundation
import SwiftData

@Model
final class Device {
    var id: String
    var name: String
    var type: String // "ESP32", "ESP8266", "Pi Pico W", "Pi Zero W", etc.
    var isOnline: Bool
    var lastSeen: Date?
    var telemetryTopics: [String]
    
    init(id: String, name: String, type: String = "ESP32") {
        self.id = id
        self.name = name
        self.type = type
        self.isOnline = false
        self.lastSeen = nil
        self.telemetryTopics = []
    }
    
    func topicForTelemetry(_ keyword: String) -> String {
        return "device/\(id)/telemetry/\(keyword)"
    }
}

