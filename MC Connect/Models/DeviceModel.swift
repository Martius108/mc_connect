//
//  DeviceModel.swift
//  MC Connect
//
//  Created by Martin Lanius on 25.10.25.
//

import SwiftData
import Foundation

@Model
final class Device {
    @Attribute(.unique) var id: String
    var name: String
    var type: String
    var host: String
    var port: Int
    var username: String
    var password: String
    var clientID: String
    var commandTopic: String // z.B. "pi/cmd"
    var telemetryTopic: String // z.B. "pi/telemetry"
    var ackTopic: String // z.B. "pi/ack"
    var externalId: String // optional: ID, die vom Microcontroller gesendet wird (z.B. "esp01")
    var isActive: Bool // optional: markiert aktives Device

    init(id: String = UUID().uuidString,
         name: String = "",
         type: String = "",
         host: String = "192.168.178.25",
         port: Int = 1883,
         username: String = "",
         password: String = "",
         clientID: String = "",
         commandTopic: String = "pi/cmd",
         telemetryTopic: String = "pi/telemetry",
         ackTopic: String = "pi/ack",
         externalId: String = "",
         isActive: Bool = false) {
        self.id = id
        self.name = name
        self.type = type
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.clientID = clientID
        self.commandTopic = commandTopic
        self.telemetryTopic = telemetryTopic
        self.ackTopic = ackTopic
        self.externalId = externalId
        self.isActive = isActive
    }
}
