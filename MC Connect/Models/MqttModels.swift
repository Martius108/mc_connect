//
//  MqttModels.swift
//  MC Connect
//
//  Created by Martin Lanius on 23.10.25.
//

import Foundation
import CocoaMQTT

struct MqttMessage: Identifiable {
    let id = UUID()
    let topic: String
    let payload: String
    let timestamp: Date = Date()
}

protocol MqttServiceType {
    var host: String { get set }
    var port: UInt16 { get set }
    var username: String { get set }
    var password: String { get set }
    var clientID: String { get set }

    var isConnected: Bool { get }
    var connectionState: ConnState { get }

    func connect(onMessage: @escaping (MqttMessage) -> Void,
                 onStatus: @escaping (_ connected: Bool, _ state: ConnState) -> Void)
    func disconnect()

    func subscribe(_ topic: String, qos: CocoaMQTTQoS)
    func unsubscribe(_ topic: String)

    func publishJSON(topic: String, object: [String: Any],
                     qos: CocoaMQTTQoS, retain: Bool)
}

enum ConnState: String {
    case disconnected = "Disconnected"
    case connecting = "Connecting..."
    case connected = "Connected"
}
