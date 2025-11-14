//
//  MqttModel.swift
//  MC_Connect
//
//  Created by Martin Lanius on 09.11.25.
//

import Foundation

// MQTT Connection State
enum MqttConnectionState {
    case disconnected
    case connecting
    case connected
    case error(String)
}

// MQTT Message Model
struct MqttMessage {
    let topic: String
    let payload: String
    let qos: Int
    let timestamp: Date
    
    init(topic: String, payload: String, qos: Int = 0) {
        self.topic = topic
        self.payload = payload
        self.qos = qos
        self.timestamp = Date()
    }
    
    // Parse topic to extract device ID and telemetry keyword
    // Supports formats:
    // - device/{deviceId}/telemetry/{keyword}
    // - device/{deviceId}/status
    // - device/{deviceId}/ack
    func parseTopic() -> (deviceId: String?, keyword: String?) {
        let components = topic.split(separator: "/")
        guard components.count >= 3,
              components[0] == "device" else {
            return (nil, nil)
        }
        
        let deviceId = String(components[1])
        
        // Handle telemetry topics: device/{deviceId}/telemetry/{keyword}
        if components.count >= 4 && components[2] == "telemetry" {
            let keyword = String(components[3])
            return (deviceId, keyword)
        }
        
        // Handle status and ack topics: device/{deviceId}/status or device/{deviceId}/ack
        if components.count == 3 {
            let topicType = String(components[2])
            if topicType == "status" || topicType == "ack" {
                // For status/ack, we still update device last seen, but don't create telemetry data
                return (deviceId, topicType)
            }
        }
        
        return (nil, nil)
    }
    
    // Try to parse payload as Double
    // Supports both simple numeric strings and JSON format: {"value": 25.50, "unit": "C"}
    // Also supports complex JSON structures like:
    // - {"pin": 26, "obstacle": true, "ts": 123456} -> obstacle (true=1, false=0)
    // - {"target": "led_ext", "pin": 16, "status": "on", "ts": 123456} -> status ("on"=1, "off"=0)
    func parseValue() -> Double? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // First try to parse as simple number
        if let value = Double(trimmed) {
            return value
        }
        
        // Try to parse as JSON
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        
        // Try "value" field first (standard format)
        if let value = json["value"] as? Double {
            return value
        }
        
        if let valueString = json["value"] as? String,
           let value = Double(valueString) {
            return value
        }
        
        // Try "obstacle" field (for proximity sensors: true=1, false=0)
        if let obstacle = json["obstacle"] as? Bool {
            return obstacle ? 1.0 : 0.0
        }
        
        // Try "status" field (for LED/GPIO status: "on"=1, "off"=0)
        if let status = json["status"] as? String {
            let statusLower = status.lowercased()
            if statusLower == "on" || statusLower == "true" || statusLower == "1" {
                return 1.0
            } else if statusLower == "off" || statusLower == "false" || statusLower == "0" {
                return 0.0
            }
        }
        
        // Try boolean status field
        if let status = json["status"] as? Bool {
            return status ? 1.0 : 0.0
        }
        
        // Try "pin" field as fallback (for debugging)
        if let pin = json["pin"] as? Int {
            return Double(pin)
        }
        
        if let pin = json["pin"] as? Double {
            return pin
        }
        
        return nil
    }
    
    // Extract unit from JSON payload if available
    func parseUnit() -> String? {
        let trimmed = payload.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = trimmed.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let unit = json["unit"] as? String else {
            return nil
        }
        
        return unit
    }
}

// MQTT Configuration
struct MqttConfiguration {
    let host: String
    let port: Int
    let username: String?
    let password: String?
    let clientId: String
    let keepAlive: Int
    let cleanSession: Bool
    
    init(host: String, port: Int = 1883, username: String? = nil, password: String? = nil, clientId: String = "", keepAlive: Int = 60, cleanSession: Bool = true) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.clientId = clientId.isEmpty ? "MC_Connect_\(UUID().uuidString.prefix(8))" : clientId
        self.keepAlive = keepAlive
        self.cleanSession = cleanSession
    }
}

