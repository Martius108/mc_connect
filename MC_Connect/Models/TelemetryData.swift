//
//  TelemetryData.swift
//  MC_Connect
//
//  Created by Martin Lanius on 09.11.25.
//

import Foundation
import SwiftData

@Model
final class TelemetryData {
    var deviceId: String
    var keyword: String
    var value: Double
    var timestamp: Date
    var unit: String
    
    init(deviceId: String, keyword: String, value: Double, unit: String = "", timestamp: Date = Date()) {
        self.deviceId = deviceId
        self.keyword = keyword
        self.value = value
        self.unit = unit
        self.timestamp = timestamp
    }
}

