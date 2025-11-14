//
//  BrokerSettings.swift
//  MC_Connect
//
//  Created by Martin Lanius on 09.11.25.
//

import Foundation
import SwiftData

@Model
final class BrokerSettings {
    var host: String
    var port: Int
    var username: String
    var password: String
    var clientId: String
    var keepAlive: Int
    var isConnected: Bool
    
    init(host: String = "", port: Int = 1883, username: String = "", password: String = "", clientId: String = "", keepAlive: Int = 60) {
        self.host = host
        self.port = port
        self.username = username
        self.password = password
        self.clientId = clientId.isEmpty ? "ios_\(UUID().uuidString.prefix(8))" : clientId
        self.keepAlive = keepAlive
        self.isConnected = false
    }
}

