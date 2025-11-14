//
//  TelemetryConfig.swift
//  MC_Connect
//
//  Created by Martin Lanius on 09.11.25.
//

import Foundation
import SwiftData

@Model
final class TelemetryConfig {
    var keywords: [String]
    var keywordUnitsJSON: String = "{}" // JSON string representation of [String: String]
    var deviceId: String
    
    init(deviceId: String = "", keywords: [String] = [], keywordUnits: [String: String] = [:]) {
        self.deviceId = deviceId
        self.keywords = keywords
        self.keywordUnitsJSON = Self.encodeUnits(keywordUnits)
    }
    
    // Computed property for easy access to keywordUnits dictionary
    var keywordUnits: [String: String] {
        get {
            // Handle empty or invalid JSON (for migration from old schema)
            if keywordUnitsJSON.isEmpty || keywordUnitsJSON == "{}" {
                return [:]
            }
            return Self.decodeUnits(keywordUnitsJSON)
        }
        set {
            keywordUnitsJSON = Self.encodeUnits(newValue)
        }
    }
    
    func getUnit(for keyword: String) -> String {
        return keywordUnits[keyword] ?? TelemetryKeyword(rawValue: keyword)?.unit ?? ""
    }
    
    // Helper methods to encode/decode dictionary to/from JSON
    private static func encodeUnits(_ units: [String: String]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: units),
              let jsonString = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return jsonString
    }
    
    private static func decodeUnits(_ jsonString: String) -> [String: String] {
        guard let data = jsonString.data(using: .utf8),
              let dictionary = try? JSONSerialization.jsonObject(with: data) as? [String: String] else {
            return [:]
        }
        return dictionary
    }
}

// Enum für Standard-Telemetrie-Keywords
enum TelemetryKeyword: String, CaseIterable, Codable {
    case temperature = "temperature"
    case humidity = "humidity"
    case pressure = "pressure"
    case voltage = "voltage"
    case current = "current"
    case power = "power"
    case state = "state"
    case proximity = "proximity"
    case led = "led"
    case gpio = "gpio"
    
    var displayName: String {
        switch self {
        case .temperature: return "temperature"
        case .humidity: return "humidity"
        case .pressure: return "pressure"
        case .voltage: return "voltage"
        case .current: return "current"
        case .power: return "power"
        case .state: return "state"
        case .proximity: return "proximity"
        case .led: return "led"
        case .gpio: return "gpio"
        }
    }
    
    var unit: String {
        switch self {
        case .temperature: return "°C"
        case .humidity: return "%"
        case .pressure: return "hPa"
        case .voltage: return "V"
        case .current: return "mA"
        case .power: return "W"
        case .state: return ""
        case .proximity: return ""
        case .led: return ""
        case .gpio: return ""
        }
    }
}

