//
//  MqttService.swift
//  MC Connect
//
//  Created by Martin Lanius on 23.10.25.
//

import Foundation
import CocoaMQTT

final class MqttService: NSObject, MqttServiceType {
    // Broker-Daten – Defaults wie in deiner CVOld
    var host: String = "192.168.178.25"
    var port: UInt16 = 1883
    var username: String = "mqsr"
    var password: String = "mqsrpss"
    var clientID: String = "ios-\(UUID().uuidString.prefix(8))"

    private var mqtt: CocoaMQTT?

    private(set) var isConnected: Bool = false
    private(set) var connectionState: ConnState = .disconnected

    private var onMessage: ((MqttMessage) -> Void)?
    private var onStatus: ((_ connected: Bool, _ state: ConnState) -> Void)?

    // Topics wie vorher
    private let topicsToSubscribe = ["pi/status", "pi/telemetry", "pi/ack"]

    func connect(onMessage: @escaping (MqttMessage) -> Void,
                 onStatus: @escaping (_ connected: Bool, _ state: ConnState) -> Void) {
        self.onMessage = onMessage
        self.onStatus = onStatus

        let client = CocoaMQTT(clientID: clientID, host: host, port: port)
        client.username = username
        client.password = password
        client.keepAlive = 60
        client.autoReconnect = true
        client.autoReconnectTimeInterval = 3
        client.cleanSession = true
        client.enableSSL = false
        client.delegate = self

        mqtt = client
        connectionState = .connecting
        onStatus(false, .connecting)
        _ = client.connect()
    }

    func disconnect() {
        mqtt?.disconnect()
    }

    func subscribe(_ topic: String, qos: CocoaMQTTQoS) {
        mqtt?.subscribe(topic, qos: qos)
    }

    func unsubscribe(_ topic: String) {
        mqtt?.unsubscribe(topic)
    }

    func publishJSON(topic: String, object: [String: Any], qos: CocoaMQTTQoS, retain: Bool) {
        guard let mqtt = mqtt else {
            onMessage?(MqttMessage(topic: "app/error", payload: "MQTT client nil"))
            return
        }
        guard isConnected else {
            onMessage?(MqttMessage(topic: "app/error", payload: "Nicht verbunden"))
            return
        }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: []),
              let payload = String(data: data, encoding: .utf8) else {
            onMessage?(MqttMessage(topic: "app/error", payload: "JSON Serialisierung fehlgeschlagen"))
            return
        }
        onMessage?(MqttMessage(topic: "app/publish", payload: "topic=\(topic) payload=\(payload)"))
        mqtt.publish(topic, withString: payload, qos: qos, retained: retain)
    }
}

// MARK: - CocoaMQTTDelegate
extension MqttService: CocoaMQTTDelegate {
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        let ok = (ack == .accept)
        DispatchQueue.main.async {
            self.isConnected = ok
            self.connectionState = ok ? .connected : .disconnected
            self.onStatus?(ok, self.connectionState)
        }
        guard ok else { return }

        // Auto-Subscribe wie vorher
        for t in topicsToSubscribe {
            mqtt.subscribe(t, qos: .qos1)
        }
    }

    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        let item = MqttMessage(topic: message.topic, payload: message.string ?? "<binary>")
        DispatchQueue.main.async {
            self.onMessage?(item)
        }
    }

    // Disconnect (neue Signatur)
    func mqtt(_ mqtt: CocoaMQTT, didDisconnectWithError err: Error?) {
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionState = .disconnected
            self.onStatus?(false, .disconnected)
        }
    }

    // Alte Signatur – optional zusätzlich
    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionState = .disconnected
            self.onStatus?(false, .disconnected)
        }
    }

    // Unbenutzte, aber implementierbare Delegates
    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {}
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {}
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {}
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {}
    func mqttDidPing(_ mqtt: CocoaMQTT) {}
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {}
}
