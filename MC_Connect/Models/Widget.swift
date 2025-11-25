//
//  Widget.swift
//  MC_Connect
//
//  Created by Martin Lanius on 09.11.25.
//

import Foundation
import SwiftData

// Widget Size Options
enum WidgetWidth: String, Codable, CaseIterable {
    case quarter = "Quarter Width"
    case half = "Half Width"
    case full = "Full Width"
    
    var columnSpan: Int {
        switch self {
        case .quarter: return 1
        case .half: return 2
        case .full: return 4
        }
    }
}

enum WidgetHeight: String, Codable, CaseIterable {
    case quarter = "Quarter Height"
    case half = "Half Height"
    case full = "Full Height"
    
    var rowSpan: Int {
        switch self {
        case .quarter: return 1
        case .half: return 2
        case .full: return 4
        }
    }
}

// Widget Type
enum WidgetType: String, Codable, CaseIterable {
    case gauge = "Gauge"
    case switchType = "Switch"
    case slider = "Slider"
    case knob = "Knob"
    case progress = "Progress Bar"
    case value = "Value"
    case sensorAnalog = "Sensor Analog"
    case sensorBinary = "Sensor Binary"
    case klima = "Climate"
    case twoValue = "2 x Value"
    case button = "Button"
    
    var displayName: String {
        return rawValue
    }
}

// Pin Mode
enum PinMode: String, Codable, CaseIterable {
    case input = "Input"
    case output = "Output"
}

// Sensor Type
enum SensorType: String, Codable, CaseIterable {
    case analog = "Analog"
    case binary = "Binary"
}

// Value Display Style
enum ValueStyle: String, Codable, CaseIterable {
    case analog = "Analog"
}

@Model
final class Widget {
    var id: UUID
    var title: String
    var widgetType: String // WidgetType rawValue
    var deviceId: String
    var telemetryKeyword: String
    var unit: String
    var minValue: Double?
    var maxValue: Double?
    var width: String // WidgetWidth rawValue
    var height: String // WidgetHeight rawValue
    var valueStyle: String? // ValueStyle rawValue (only for value type)
    var pin: Int? // PIN number for switches and sensors
    var pinMode: String? // PinMode rawValue (Input/Output) for switches
    var sensorType: String? // SensorType rawValue (Analog/Binary) for sensors
    var invertedLogic: Bool // Inverted logic for sensors (LOW = true or HIGH = true)
    var secondaryTelemetryKeyword: String? // Second keyword for klima and twoValue widgets
    var secondaryUnit: String? // Second unit for twoValue widgets
    var temperatureMinValue: Double? // Min value for temperature in klima widget
    var temperatureMaxValue: Double? // Max value for temperature in klima widget
    var humidityMinValue: Double? // Min value for humidity in klima widget
    var humidityMaxValue: Double? // Max value for humidity in klima widget
    var buttonDuration: Double? // Button press duration in milliseconds
    var stepSize: Double? // Step size for slider/knob widgets (default: 1.0)
    
    init(
        id: UUID = UUID(),
        title: String,
        widgetType: WidgetType,
        deviceId: String,
        telemetryKeyword: String,
        unit: String = "",
        minValue: Double? = nil,
        maxValue: Double? = nil,
        width: WidgetWidth = .half,
        height: WidgetHeight = .half,
        valueStyle: ValueStyle? = nil,
        pin: Int? = nil,
        pinMode: PinMode? = nil,
        sensorType: SensorType? = nil,
        invertedLogic: Bool = false,
        secondaryTelemetryKeyword: String? = nil,
        secondaryUnit: String? = nil,
        temperatureMinValue: Double? = nil,
        temperatureMaxValue: Double? = nil,
        humidityMinValue: Double? = nil,
        humidityMaxValue: Double? = nil,
        buttonDuration: Double? = nil,
        stepSize: Double? = nil
    ) {
        self.id = id
        self.title = title
        self.widgetType = widgetType.rawValue
        self.deviceId = deviceId
        self.telemetryKeyword = telemetryKeyword
        self.unit = unit
        self.minValue = minValue
        self.maxValue = maxValue
        self.width = width.rawValue
        self.height = height.rawValue
        self.valueStyle = valueStyle?.rawValue
        self.pin = pin
        self.pinMode = pinMode?.rawValue
        self.sensorType = sensorType?.rawValue
        self.invertedLogic = invertedLogic
        self.secondaryTelemetryKeyword = secondaryTelemetryKeyword
        self.secondaryUnit = secondaryUnit
        self.temperatureMinValue = temperatureMinValue
        self.temperatureMaxValue = temperatureMaxValue
        self.humidityMinValue = humidityMinValue
        self.humidityMaxValue = humidityMaxValue
        self.buttonDuration = buttonDuration
        self.stepSize = stepSize
    }
    
    var type: WidgetType {
        get { WidgetType(rawValue: widgetType) ?? .value }
        set { widgetType = newValue.rawValue }
    }
    
    var widgetWidth: WidgetWidth {
        get { WidgetWidth(rawValue: width) ?? .half }
        set { width = newValue.rawValue }
    }
    
    var widgetHeight: WidgetHeight {
        get { WidgetHeight(rawValue: height) ?? .half }
        set { height = newValue.rawValue }
    }
    
    var style: ValueStyle? {
        get {
            guard let valueStyle = valueStyle else { return nil }
            return ValueStyle(rawValue: valueStyle)
        }
        set { valueStyle = newValue?.rawValue }
    }
    
    var mode: PinMode? {
        get {
            guard let pinMode = pinMode else { return nil }
            return PinMode(rawValue: pinMode)
        }
        set { pinMode = newValue?.rawValue }
    }
    
    var sensorTypeEnum: SensorType? {
        get {
            guard let sensorType = sensorType else { return nil }
            return SensorType(rawValue: sensorType)
        }
        set { sensorType = newValue?.rawValue }
    }
}

