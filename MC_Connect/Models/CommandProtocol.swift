//
//  CommandProtocol.swift
//  MC_Connect
//
//  Standardized MQTT Command Protocol
//  This defines the structure that all microcontrollers should follow
//

import Foundation

// MARK: - Command Types
enum CommandType: String, Codable {
    case gpio = "gpio"
    case sensor = "sensor"
    case actuator = "actuator"
    case system = "system"
}

// MARK: - GPIO Command
struct GpioCommand: Codable {
    let type: CommandType
    let pin: Int
    let value: Int // 0 or 1 for digital, 0-1024 for analog
    let mode: String? // "input" or "output" (optional, for documentation)
    
    init(pin: Int, value: Int, mode: String? = nil) {
        self.type = .gpio
        self.pin = pin
        self.value = value
        self.mode = mode
    }
}

// MARK: - Sensor Command
struct SensorCommand: Codable {
    let type: CommandType
    let pin: Int
    let action: String // "read", "configure", etc.
    let config: String? // Optional configuration as JSON string
    
    init(pin: Int, action: String, config: [String: Any]? = nil) {
        self.type = .sensor
        self.pin = pin
        self.action = action
        // Convert config dictionary to JSON string
        if let config = config,
           let jsonData = try? JSONSerialization.data(withJSONObject: config),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            self.config = jsonString
        } else {
            self.config = nil
        }
    }
}

// MARK: - Standard Command Protocol
protocol MqttCommandProtocol {
    func toJSON() -> String?
    func getTopic(deviceId: String) -> String
}

extension GpioCommand: MqttCommandProtocol {
    func toJSON() -> String? {
        guard let jsonData = try? JSONEncoder().encode(self),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }
        return jsonString
    }
    
    func getTopic(deviceId: String) -> String {
        return "device/\(deviceId)/command"
    }
}

extension SensorCommand: MqttCommandProtocol {
    func toJSON() -> String? {
        guard let jsonData = try? JSONEncoder().encode(self),
              let jsonString = String(data: jsonData, encoding: .utf8) else {
            return nil
        }
        return jsonString
    }
    
    func getTopic(deviceId: String) -> String {
        return "device/\(deviceId)/command"
    }
}

// MARK: - Command Factory (for easy creation)
struct CommandFactory {
    static func createGpioCommand(pin: Int, value: Int, mode: String? = nil) -> GpioCommand {
        return GpioCommand(pin: pin, value: value, mode: mode)
    }
    
    static func createSensorCommand(pin: Int, action: String, config: [String: Any]? = nil) -> SensorCommand {
        return SensorCommand(pin: pin, action: action, config: config)
    }
}

