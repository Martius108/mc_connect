//
//  WidgetViews.swift
//  MC_Connect
//
//  Created by Martin Lanius on 09.11.25.
//

import SwiftUI

// Base Widget Container
struct WidgetContainer<Content: View>: View {
    let widget: Widget
    let content: Content
    
    init(widget: Widget, @ViewBuilder content: () -> Content) {
        self.widget = widget
        self.content = content()
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(widget.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
            
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

// Custom Circular Gauge Shape - Filled Ring
struct CircularGaugeShape: Shape {
    var progress: Double
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let lineWidth: CGFloat = radius * 0.25  // Thicker ring
        let innerRadius = radius - lineWidth / 2
        let outerRadius = radius + lineWidth / 2
        
        // Start at 8 o'clock position (210 degrees or -150 degrees)
        let startAngle = Angle.degrees(-210)
        let endAngle = Angle.degrees(-210 + 360 * progress)
        
        // Create the filled arc segment
        path.addArc(
            center: center,
            radius: innerRadius,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: false
        )
        
        // Add outer arc
        path.addArc(
            center: center,
            radius: outerRadius,
            startAngle: endAngle,
            endAngle: startAngle,
            clockwise: true
        )
        
        path.closeSubpath()
        
        return path
    }
}

// Gauge Widget (Circular, Blue)
struct GaugeWidget: View {
    let widget: Widget
    let value: Double?
    
    private var normalizedValue: Double {
        guard let value = value else {
            return 0.0
        }
        // Fallback to 0-100 if min/max not set
        let minVal = widget.minValue ?? 0.0
        let maxVal = widget.maxValue ?? 100.0
        guard maxVal > minVal else {
            return 0.0
        }
        return Swift.max(0.0, Swift.min(1.0, (value - minVal) / (maxVal - minVal)))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(widget.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.top, 12)
                .padding(.bottom, 4)
            
            GeometryReader { geometry in
                ZStack {
                    if let unwrappedValue = value {
                        let size = min(geometry.size.width, geometry.size.height) * 0.75
                        let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        let radius = size / 2
                        let lineWidth = radius * 0.25  // Thicker ring
                        
                        // Background circle (full ring)
                        Circle()
                            .stroke(Color.gray.opacity(0.2), lineWidth: lineWidth)
                            .frame(width: size, height: size)
                            .position(center)
                        
                        // Progress arc (filled segment)
                        CircularGaugeShape(progress: normalizedValue)
                            .fill(Color.blue)
                            .frame(width: size, height: size)
                            .position(center)
                        
                        // Value text
                        VStack(spacing: 4) {
                            Text("\(String(format: "%.2f", unwrappedValue))")
                                .font(.system(size: size * 0.18, weight: .bold, design: .rounded))
                                .foregroundColor(.primary)
                            if !widget.unit.isEmpty {
                                Text(widget.unit)
                                    .font(.system(size: size * 0.1))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .position(center)
                    } else {
                        // No Data - centered and smaller font
                        VStack {
                            Text("No Data")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .padding(0)
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

// Switch Widget (Toggle with Feedback, Blue when On)
struct SwitchWidget: View {
    let widget: Widget
    let value: Double?
    @EnvironmentObject var mqttViewModel: MqttViewModel
    @State private var isOn: Bool = false
    @State private var isUpdatingFromTelemetry: Bool = false  // Flag to prevent feedback loop
    
    private var isOutput: Bool {
        widget.mode == .output
    }
    
    private var pinNumber: String {
        if let pin = widget.pin {
            return "PIN \(pin)"
        }
        return ""
    }
    
    var body: some View {
        WidgetContainer(widget: widget) {
            VStack(spacing: 12) {
                if !pinNumber.isEmpty {
                    Text(pinNumber)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Toggle("", isOn: $isOn)
                    .toggleStyle(.switch)
                    .tint(.blue)
                    .scaleEffect(0.8)
                    .disabled(!isOutput)
                    .onChange(of: isOn) { oldValue, newValue in
                        // Nur Command senden, wenn es eine Benutzer-Änderung ist (nicht durch Telemetry-Update)
                        if isOutput && !isUpdatingFromTelemetry {
                            sendSwitchCommand(newValue)
                        }
                    }
                
                Text(isOn ? "ON" : "OFF")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(isOn ? .blue : .gray)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onAppear {
                updateSwitchState()
            }
            .onChange(of: value) { oldValue, newValue in
                updateSwitchState()
            }
        }
    }
    
    private func updateSwitchState() {
        guard !isUpdatingFromTelemetry else { return }
        
        if let value = value {
            // Treat any non-zero value as HIGH (1), zero as LOW (0)
            let gpioValue = value != 0.0
            
            // Apply inverted logic if enabled
            // If inverted: LOW (0) means ON (true), HIGH (1) means OFF (false)
            // If not inverted: HIGH (1) means ON (true), LOW (0) means OFF (false)
            let newState: Bool
            if widget.invertedLogic {
                newState = !gpioValue  // Inverted: LOW = ON, HIGH = OFF
            } else {
                newState = gpioValue   // Normal: HIGH = ON, LOW = OFF
            }
            
            // Nur aktualisieren, wenn sich der State tatsächlich geändert hat
            if isOn != newState {
                isUpdatingFromTelemetry = true
                isOn = newState
                // Kurze Verzögerung, um sicherzustellen, dass der onChange-Handler nicht getriggert wird
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isUpdatingFromTelemetry = false
                }
            }
        } else {
            if isOn {
                isUpdatingFromTelemetry = true
                isOn = false
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isUpdatingFromTelemetry = false
                }
            }
        }
    }
    
    private func sendSwitchCommand(_ state: Bool) {
        guard let pin = widget.pin else { return }
        
        // Use standardized command structure: device/{id}/command
        // Payload format: {"type": "gpio", "pin": X, "value": 0|1, "mode": "output"}
        let topic = "device/\(widget.deviceId)/command"
        
        // Apply inverted logic if enabled
        // If inverted: ON (true) sends LOW (0), OFF (false) sends HIGH (1)
        // If not inverted: ON (true) sends HIGH (1), OFF (false) sends LOW (0)
        let gpioValue: Int
        if widget.invertedLogic {
            gpioValue = state ? 0 : 1
        } else {
            gpioValue = state ? 1 : 0
        }
        
        // Create standardized GPIO command
        let command = CommandFactory.createGpioCommand(
            pin: pin,
            value: gpioValue,
            mode: widget.mode?.rawValue.lowercased()
        )
        
        guard let payload = command.toJSON() else {
            return
        }
        
        _ = mqttViewModel.publishCommand(topic: topic, payload: payload)
    }
}

// Slider Widget (Input Control for PWM/Analog Output)
struct SliderWidget: View {
    let widget: Widget
    let value: Double?
    @EnvironmentObject var mqttViewModel: MqttViewModel
    @State private var sliderValue: Double = 0.0
    @State private var isUpdatingFromTelemetry: Bool = false  // Flag to prevent feedback loop
    
    private var isOutput: Bool {
        widget.mode == .output
    }
    
    private var minValue: Double {
        widget.minValue ?? 0.0
    }
    
    private var maxValue: Double {
        widget.maxValue ?? 1024.0
    }
    
    private var pinNumber: String {
        if let pin = widget.pin {
            return "PIN \(pin)"
        }
        return ""
    }
    
    var body: some View {
        WidgetContainer(widget: widget) {
            GeometryReader { geometry in
                let baseSize = min(geometry.size.width, geometry.size.height)
                
                VStack(spacing: min(baseSize * 0.1, 16)) {
                    if !pinNumber.isEmpty {
                        Text(pinNumber)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Current value display
                    VStack(spacing: 4) {
                        Text("\(String(format: "%.0f", sliderValue))")
                            .font(.system(size: min(baseSize * 0.25, 32), weight: .bold, design: .rounded))
                            .foregroundColor(.blue)
                            .minimumScaleFactor(0.5)
                            .lineLimit(1)
                        
                        if !widget.unit.isEmpty {
                            Text(widget.unit)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    // Slider
                    Slider(
                        value: $sliderValue,
                        in: minValue...maxValue,
                        step: 1.0
                    )
                    .tint(.blue)
                    .disabled(!isOutput)
                    .onChange(of: sliderValue) { oldValue, newValue in
                        // Nur Command senden, wenn es eine Benutzer-Änderung ist (nicht durch Telemetry-Update)
                        if isOutput && !isUpdatingFromTelemetry {
                            sendSliderCommand(newValue)
                        }
                    }
                    
                    // Min/Max labels
                    HStack {
                        Text("\(String(format: "%.0f", minValue))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(String(format: "%.0f", maxValue))")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear {
                updateSliderValue()
            }
            .onChange(of: value) { oldValue, newValue in
                updateSliderValue()
            }
        }
    }
    
    private func updateSliderValue() {
        guard let value = value else {
            if !isUpdatingFromTelemetry {
                isUpdatingFromTelemetry = true
                sliderValue = minValue
                isUpdatingFromTelemetry = false
            }
            return
        }
        
        // Clamp value to min/max range
        let newSliderValue = Swift.max(minValue, Swift.min(maxValue, value))
        
        // Nur aktualisieren, wenn sich der Wert signifikant unterscheidet (Toleranz: 1)
        // Das verhindert Feedback-Schleifen durch kleine Rundungsunterschiede
        if abs(sliderValue - newSliderValue) > 1.0 {
            isUpdatingFromTelemetry = true
            sliderValue = newSliderValue
            // Kurze Verzögerung, um sicherzustellen, dass der onChange-Handler nicht getriggert wird
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isUpdatingFromTelemetry = false
            }
        }
    }
    
    private func sendSliderCommand(_ value: Double) {
        guard let pin = widget.pin else { return }
        
        // Convert value to Int (0-1024 for PWM)
        let pwmValue = Int(Swift.max(0, Swift.min(1024, value)))
        
        // Use standardized command structure: device/{id}/command
        // Payload format: {"type": "gpio", "pin": X, "value": 0-1024, "mode": "output"}
        let topic = "device/\(widget.deviceId)/command"
        
        // Create standardized GPIO command with PWM value
        let command = CommandFactory.createGpioCommand(
            pin: pin,
            value: pwmValue,
            mode: widget.mode?.rawValue.lowercased()
        )
        
        guard let payload = command.toJSON() else {
            return
        }
        
        _ = mqttViewModel.publishCommand(topic: topic, payload: payload)
    }
}

// Progress Bar Widget (Linear, Blue)
struct ProgressBarWidget: View {
    let widget: Widget
    let value: Double?
    
    private var progress: Double {
        guard let value = value,
              let minVal = widget.minValue,
              let maxVal = widget.maxValue,
              maxVal > minVal else {
            return 0.0
        }
        return Swift.max(0.0, Swift.min(1.0, (value - minVal) / (maxVal - minVal)))
    }
    
    var body: some View {
        WidgetContainer(widget: widget) {
            GeometryReader { geometry in
                let availableHeight = geometry.size.height
                let fontSize = min(availableHeight * 0.15, 20) // Anpassung basierend auf verfügbarer Höhe
                
                VStack(spacing: min(availableHeight * 0.1, 12)) {
                    if let unwrappedValue = value {
                        ProgressView(value: progress)
                            .progressViewStyle(.linear)
                            .tint(.blue)
                            .scaleEffect(y: min(availableHeight * 0.25, 3.5))
                        
                        HStack {
                            if let min = widget.minValue {
                                Text("\(String(format: "%.1f", min))")
                                    .font(.system(size: fontSize * 0.7))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Text("\(String(format: "%.2f", unwrappedValue))")
                                .font(.system(size: fontSize, weight: .semibold))
                                .minimumScaleFactor(0.6)
                                .lineLimit(1)
                            if !widget.unit.isEmpty {
                                Text(widget.unit)
                                    .font(.system(size: fontSize * 0.7))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            if let max = widget.maxValue {
                                Text("\(String(format: "%.1f", max))")
                                    .font(.system(size: fontSize * 0.7))
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        Text("No Data")
                            .font(.system(size: fontSize * 0.8))
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// Value Widget (Analog)
struct ValueWidget: View {
    let widget: Widget
    let value: Double?
    let style: ValueStyle
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(widget.title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(.primary)
            
            GeometryReader { geometry in
                let availableHeight = geometry.size.height
                // Use height as primary factor for font size, ensure it's proportional to headline (17pt)
                // Aim for 2.5-3x the headline size for good readability
                let fontSize = min(availableHeight * 0.5, 48) // 50% of available height, max 48pt
                let unitSize = fontSize * 0.5 // Unit is half the value size
                
                VStack {
                    if let unwrappedValue = value {
                        // Analog style - large number with unit, size adapts to available space
                        VStack(spacing: 4) {
                            HStack(alignment: .firstTextBaseline, spacing: 4) {
                                Text(String(format: "%.2f", unwrappedValue))
                                    .font(.system(size: max(fontSize, 24), weight: .bold, design: .rounded))
                                    .minimumScaleFactor(0.6)
                                    .lineLimit(1)
                                if !widget.unit.isEmpty {
                                    Text(widget.unit)
                                        .font(.system(size: max(unitSize, 16)))
                                        .foregroundColor(.secondary)
                                        .minimumScaleFactor(0.6)
                                        .lineLimit(1)
                                }
                            }
                        }
                    } else {
                        Text("No Data")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.1), radius: 5, x: 0, y: 2)
    }
}

// Sensor Analog Widget
struct SensorAnalogWidget: View {
    let widget: Widget
    let value: Double?
    
    private var displayValue: Double {
        guard let value = value else { return 0.0 }
        return widget.invertedLogic ? (widget.maxValue ?? 1024.0) - value : value
    }
    
    var body: some View {
        WidgetContainer(widget: widget) {
            GeometryReader { geometry in
                let baseSize = min(geometry.size.width, geometry.size.height)
                
                VStack(spacing: min(baseSize * 0.08, 12)) {
                    if let pin = widget.pin {
                        Text("PIN \(pin)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if value != nil {
                        VStack(spacing: 8) {
                            Text(String(format: "%.2f", displayValue))
                                .font(.system(size: min(baseSize * 0.3, 36), weight: .bold, design: .rounded))
                                .minimumScaleFactor(0.5)
                                .lineLimit(1)
                            
                            if !widget.unit.isEmpty {
                                Text(widget.unit)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            if widget.invertedLogic {
                                Text("Inverted")
                                    .font(.caption2)
                                    .foregroundColor(.orange)
                            }
                        }
                    } else {
                        Text("No Data")
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// Sensor Binary Widget
struct SensorBinaryWidget: View {
    let widget: Widget
    let value: Double?
    
    private var isProximitySensor: Bool {
        widget.telemetryKeyword.lowercased().contains("proximity")
    }
    
    private var isActive: Bool {
        guard let value = value else { return false }
        let minVal = widget.minValue ?? 0.0
        let maxVal = widget.maxValue ?? 1.0
        let threshold = (minVal + maxVal) / 2.0
        let active = value > threshold
        return widget.invertedLogic ? !active : active
    }
    
    // For proximity sensors: red = obstacle detected, green = no obstacle
    private var hasObstacle: Bool {
        isActive
    }
    
    var body: some View {
        WidgetContainer(widget: widget) {
            GeometryReader { geometry in
                let baseSize = min(geometry.size.width, geometry.size.height)
                let circleSize = isProximitySensor ? min(baseSize * 0.5, 80) : 60
                
                if isProximitySensor {
                    // Proximity sensor layout: square container, colored circle, "Obstacle" only for red
                    VStack(spacing: 8) {
                        if let pin = widget.pin {
                            Text("PIN \(pin)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Circle()
                            .fill(hasObstacle ? Color.red : Color.green)
                            .frame(width: circleSize, height: circleSize)
                        
                        if hasObstacle {
                            Text("Obstacle")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.red)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    // Standard binary sensor layout
                    VStack(spacing: 12) {
                        if let pin = widget.pin {
                            Text("PIN \(pin)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        Circle()
                            .fill(isActive ? Color.green : Color.red)
                            .frame(width: circleSize, height: circleSize)
                            .overlay(
                                Text(isActive ? "HIGH" : "LOW")
                                    .font(.caption)
                                    .fontWeight(.bold)
                                    .foregroundColor(.white)
                            )
                        
                        Text(isActive ? "Active" : "Inactive")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(isActive ? .green : .red)
                        
                        if widget.invertedLogic {
                            Text("Inverted Logic")
                                .font(.caption2)
                                .foregroundColor(.orange)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }
}

// Klima Widget (Two Gauges: Temperature and Humidity)
struct KlimaWidget: View {
    let widget: Widget
    let temperatureData: TelemetryData?
    let humidityData: TelemetryData?
    
    private var normalizedTemperature: Double {
        guard let value = temperatureData?.value else {
            return 0.0
        }
        // Use separate temperature min/max if set, otherwise fallback to general min/max or 0-100
        let minVal = widget.temperatureMinValue ?? widget.minValue ?? 0.0
        let maxVal = widget.temperatureMaxValue ?? widget.maxValue ?? 100.0
        guard maxVal > minVal else {
            return 0.0
        }
        return Swift.max(0.0, Swift.min(1.0, (value - minVal) / (maxVal - minVal)))
    }
    
    private var normalizedHumidity: Double {
        guard let value = humidityData?.value else {
            return 0.0
        }
        // Use separate humidity min/max if set, otherwise fallback to general min/max or 0-100
        let minVal = widget.humidityMinValue ?? widget.minValue ?? 0.0
        let maxVal = widget.humidityMaxValue ?? widget.maxValue ?? 100.0
        guard maxVal > minVal else {
            return 0.0
        }
        return Swift.max(0.0, Swift.min(1.0, (value - minVal) / (maxVal - minVal)))
    }
    
    var body: some View {
        WidgetContainer(widget: widget) {
            HStack(spacing: 20) {
                // Temperature Gauge (left)
                if let tempValue = temperatureData?.value {
                    GeometryReader { geometry in
                        let size = min(geometry.size.width, geometry.size.height) * 0.95
                        let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        let radius = size / 2
                        let lineWidth = radius * 0.25  // Thicker ring
                        
                        ZStack {
                            // Background circle (full ring)
                            Circle()
                                .stroke(Color.gray.opacity(0.2), lineWidth: lineWidth)
                                .frame(width: size, height: size)
                                .position(center)
                            
                            // Progress arc (filled segment)
                            CircularGaugeShape(progress: normalizedTemperature)
                                .fill(Color.blue)
                                .frame(width: size, height: size)
                                .position(center)
                            
                            // Value text
                            VStack(spacing: 4) {
                                Text("\(String(format: "%.1f", tempValue))")
                                    .font(.system(size: size * 0.18, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                                Text("°C")
                                    .font(.system(size: size * 0.1))
                                    .foregroundColor(.secondary)
                            }
                            .position(center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    VStack {
                        Text("No Data")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
                
                // Humidity Gauge (right)
                if let humValue = humidityData?.value {
                    GeometryReader { geometry in
                        let size = min(geometry.size.width, geometry.size.height) * 0.95
                        let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height / 2)
                        let radius = size / 2
                        let lineWidth = radius * 0.25  // Thicker ring
                        
                        ZStack {
                            // Background circle (full ring)
                            Circle()
                                .stroke(Color.gray.opacity(0.2), lineWidth: lineWidth)
                                .frame(width: size, height: size)
                                .position(center)
                            
                            // Progress arc (filled segment)
                            CircularGaugeShape(progress: normalizedHumidity)
                                .fill(Color.blue)
                                .frame(width: size, height: size)
                                .position(center)
                            
                            // Value text
                            VStack(spacing: 4) {
                                Text("\(String(format: "%.1f", humValue))")
                                    .font(.system(size: size * 0.18, weight: .bold, design: .rounded))
                                    .foregroundColor(.primary)
                                Text("%")
                                    .font(.system(size: size * 0.1))
                                    .foregroundColor(.secondary)
                            }
                            .position(center)
                        }
                    }
                    .frame(maxWidth: .infinity)
                } else {
                    VStack {
                        Text("No Data")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// Two Value Widget (Two Value Fields Side by Side)
struct TwoValueWidget: View {
    let widget: Widget
    let firstValueData: TelemetryData?
    let secondValueData: TelemetryData?
    let style: ValueStyle
    
    var body: some View {
        WidgetContainer(widget: widget) {
            GeometryReader { geometry in
                let baseSize = min(geometry.size.width, geometry.size.height)
                let valueSize = min(baseSize * 0.2, 24)
                
                HStack(spacing: min(baseSize * 0.13, 16)) {
                    // First Value
                    VStack(spacing: 4) {
                        if let value = firstValueData?.value {
                            let displayUnit = widget.unit.isEmpty ? (firstValueData?.unit ?? "") : widget.unit
                            // Analog style - large number with unit
                            VStack(spacing: 4) {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(String(format: "%.2f", value))
                                        .font(.system(size: valueSize, weight: .bold, design: .rounded))
                                        .minimumScaleFactor(0.5)
                                        .lineLimit(1)
                                    if !displayUnit.isEmpty {
                                        Text(displayUnit)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        } else {
                            Text("No Data")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    
                    // Second Value
                    VStack(spacing: 4) {
                        if let value = secondValueData?.value {
                            let displayUnit = (widget.secondaryUnit ?? "").isEmpty ? (secondValueData?.unit ?? "") : (widget.secondaryUnit ?? "")
                            // Analog style - large number with unit
                            VStack(spacing: 4) {
                                HStack(alignment: .firstTextBaseline, spacing: 4) {
                                    Text(String(format: "%.2f", value))
                                        .font(.system(size: valueSize, weight: .bold, design: .rounded))
                                        .minimumScaleFactor(0.5)
                                        .lineLimit(1)
                                    if !displayUnit.isEmpty {
                                        Text(displayUnit)
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                        } else {
                            Text("No Data")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// Button Widget (Press Button with Duration)
struct ButtonWidget: View {
    let widget: Widget
    let value: Double?
    @EnvironmentObject var mqttViewModel: MqttViewModel
    @State private var isPressed: Bool = false
    @State private var isProcessing: Bool = false
    
    private var isOutput: Bool {
        widget.mode == .output
    }
    
    private var pinNumber: String {
        if let pin = widget.pin {
            return "PIN \(pin)"
        }
        return ""
    }
    
    private var buttonDuration: Double {
        // Duration in milliseconds, default 100ms
        widget.buttonDuration ?? 100.0
    }
    
    private var currentState: Bool {
        if let value = value {
            // Treat any non-zero value as HIGH (1), zero as LOW (0)
            let gpioValue = value != 0.0
            
            // Apply inverted logic if enabled
            // If inverted: LOW (0) means active (true), HIGH (1) means inactive (false)
            // If not inverted: HIGH (1) means active (true), LOW (0) means inactive (false)
            if widget.invertedLogic {
                return !gpioValue  // Inverted: LOW = active, HIGH = inactive
            } else {
                return gpioValue   // Normal: HIGH = active, LOW = inactive
            }
        }
        return false
    }
    
    var body: some View {
        WidgetContainer(widget: widget) {
            GeometryReader { geometry in
                let baseSize = min(geometry.size.width, geometry.size.height)
                let circleSize = min(baseSize * 0.5, 100)
                
                VStack(spacing: 12) {
                    if !pinNumber.isEmpty {
                        Text(pinNumber)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Button(action: {
                        guard isOutput && !isProcessing else { return }
                        pressButton()
                    }) {
                        Circle()
                            .fill(isPressed || currentState ? Color.blue : Color.gray)
                            .frame(width: circleSize, height: circleSize)
                            .overlay(
                                Text("PRESS")
                                    .font(.system(size: circleSize * 0.2, weight: .bold))
                                    .foregroundColor(.white)
                            )
                    }
                    .disabled(!isOutput || isProcessing)
                    
                    Text("\(String(format: "%.0f", buttonDuration)) ms")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .onAppear {
                updateButtonState()
            }
            .onChange(of: value) { _, _ in
                updateButtonState()
            }
        }
    }
    
    private func updateButtonState() {
        isPressed = currentState
    }
    
    private func pressButton() {
        guard let pin = widget.pin else { return }
        
        isProcessing = true
        isPressed = true
        
        // Apply inverted logic if enabled
        // If inverted: First send LOW (0), then HIGH (1)
        // If not inverted: First send HIGH (1), then LOW (0)
        let firstValue: Int = widget.invertedLogic ? 0 : 1
        let secondValue: Int = widget.invertedLogic ? 1 : 0
        
        // Send first command
        sendButtonCommand(pin: pin, value: firstValue)
        
        // After duration, send second command
        let durationInSeconds = buttonDuration / 1000.0
        DispatchQueue.main.asyncAfter(deadline: .now() + durationInSeconds) {
            sendButtonCommand(pin: pin, value: secondValue)
            isPressed = false
            isProcessing = false
        }
    }
    
    private func sendButtonCommand(pin: Int, value: Int) {
        // Use standardized command structure: device/{id}/command
        // Payload format: {"type": "gpio", "pin": X, "value": 0|1, "mode": "output"}
        let topic = "device/\(widget.deviceId)/command"
        
        // Create standardized GPIO command
        let command = CommandFactory.createGpioCommand(
            pin: pin,
            value: value,
            mode: widget.mode?.rawValue.lowercased()
        )
        
        guard let payload = command.toJSON() else {
            return
        }
        
        _ = mqttViewModel.publishCommand(topic: topic, payload: payload)
    }
}

// Universal Widget View that selects the right widget type
struct UniversalWidgetView: View {
    let widget: Widget
    @ObservedObject var mqttViewModel: MqttViewModel
    
    // Stable identity for the view to prevent unnecessary re-creation
    private var viewId: String {
        "\(widget.id)-\(widget.deviceId)-\(widget.telemetryKeyword)"
    }
    
    // Computed properties that access the @Published property directly
    // This ensures SwiftUI observes changes to the telemetry data
    // We access connectionState to ensure the ViewModel is fully observed
    private var connectionState: MqttConnectionState {
        mqttViewModel.connectionState
    }
    
    // Access the entire dictionary to force observation
    // This ensures SwiftUI recognizes when the dictionary structure changes
    private var allTelemetryData: [String: [String: TelemetryData]] {
        mqttViewModel.latestTelemetryData
    }
    
    private var telemetryData: TelemetryData? {
        // Access connectionState first to ensure ViewModel observation
        _ = connectionState
        // Access the entire dictionary to ensure we observe all changes
        _ = allTelemetryData
        // Now access the specific data we need
        let deviceData = mqttViewModel.latestTelemetryData[widget.deviceId]
        return deviceData?[widget.telemetryKeyword]
    }
    
    private var secondaryTelemetryData: TelemetryData? {
        guard let secondaryKeyword = widget.secondaryTelemetryKeyword else { return nil }
        // Access connectionState first to ensure ViewModel observation
        _ = connectionState
        // Access the entire dictionary to ensure we observe all changes
        _ = allTelemetryData
        // Now access the specific data we need
        let deviceData = mqttViewModel.latestTelemetryData[widget.deviceId]
        return deviceData?[secondaryKeyword]
    }
    
    var body: some View {
        // CRITICAL: Access the dictionary directly in body to ensure SwiftUI observes changes
        // This ensures that when the dictionary structure changes (e.g., when a new device is added),
        // SwiftUI will re-render the view even if the specific device/keyword data hasn't changed
        let _ = connectionState // Force observation of connection state
        let _ = allTelemetryData // Force observation of entire dictionary
        
        // Access data directly from dictionary in body to ensure proper observation
        let deviceData = mqttViewModel.latestTelemetryData[widget.deviceId]
        let primaryData = deviceData?[widget.telemetryKeyword]
        let secondaryData = widget.secondaryTelemetryKeyword.flatMap { deviceData?[$0] }
        
        return Group {
            switch widget.type {
            case .gauge:
                GaugeWidget(widget: widget, value: primaryData?.value)
            case .switchType:
                SwitchWidget(widget: widget, value: primaryData?.value)
            case .slider:
                SliderWidget(widget: widget, value: primaryData?.value)
            case .progress:
                ProgressBarWidget(widget: widget, value: primaryData?.value)
            case .value:
                ValueWidget(
                    widget: widget,
                    value: primaryData?.value,
                    style: widget.style ?? .analog
                )
            case .sensorAnalog:
                SensorAnalogWidget(widget: widget, value: primaryData?.value)
            case .sensorBinary:
                SensorBinaryWidget(widget: widget, value: primaryData?.value)
            case .klima:
                KlimaWidget(
                    widget: widget,
                    temperatureData: primaryData,
                    humidityData: secondaryData
                )
            case .twoValue:
                TwoValueWidget(
                    widget: widget,
                    firstValueData: primaryData,
                    secondValueData: secondaryData,
                    style: widget.style ?? .analog
                )
            case .button:
                ButtonWidget(widget: widget, value: primaryData?.value)
            }
        }
    }
}

