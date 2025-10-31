//
//  MqttService.swift
//  MC Connect
//
//  Created by Martin Lanius on 23.10.25.
//

import Foundation
import Combine
import CocoaMQTT

final class MqttService: NSObject, MqttServiceType, ObservableObject {
    // Broker config
    @Published var host: String = "192.168.178.25"
    @Published var port: UInt16 = 1883
    @Published var username: String = ""
    @Published var password: String = ""
    @Published var clientID: String = "ios-\(UUID().uuidString.prefix(8))"

    // ✅ Device-Zuordnung (externalId). Observable damit UI darauf reagieren kann.
    @Published public private(set) var connectedDeviceId: String?
    private(set) var topicsToSubscribe: [String] = []

    private var mqtt: CocoaMQTT?
    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var connectionState: ConnState = .disconnected

    private var onMessage: ((MqttMessage) -> Void)?
    private var onStatus: ((_ connected: Bool, _ state: ConnState) -> Void)?

    // MARK: - Configuration
    func setConfig(host: String, port: Int, clientID: String, username: String, password: String) {
        let trimmedHost = host.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedClient = clientID.trimmingCharacters(in: .whitespacesAndNewlines)
        print("[MQTT DEBUG] setConfig -> host:\(trimmedHost) port:\(port) clientID:\(trimmedClient) username:\(username.isEmpty ? "<empty>" : "<set>") password:\(password.isEmpty ? "<empty>" : "<hidden>")")

        DispatchQueue.main.async {
            self.host = trimmedHost
            self.port = UInt16(clamping: port)
            self.clientID = trimmedClient
            self.username = username
            self.password = password
        }
    }

    // MARK: - Connect / Disconnect
    func connect(onMessage: @escaping (MqttMessage) -> Void,
                 onStatus: @escaping (_ connected: Bool, _ state: ConnState) -> Void) {
        print("[MQTT DEBUG] connect() called -> host:\(host) port:\(port) clientID:\(clientID) username:\(username.isEmpty ? "<empty>" : "<set>")")

        // clean up existing client to avoid racing instances
        if let existing = mqtt {
            print("[MQTT DEBUG] connect() -> cleaning up existing client")
            existing.delegate = nil
            existing.disconnect()
            mqtt = nil
            DispatchQueue.main.async {
                self.isConnected = false
                self.connectionState = .disconnected
            }
        }

        self.onMessage = onMessage
        self.onStatus = onStatus

        let client = CocoaMQTT(clientID: clientID, host: host, port: port)
        client.username = username
        client.password = password
        client.keepAlive = 60
        client.autoReconnect = false
        client.autoReconnectTimeInterval = 3
        client.cleanSession = true
        client.enableSSL = false
        client.delegate = self

        mqtt = client
        connectionState = .connecting
        onStatus(false, .connecting)

        let ok = client.connect()
        print("[MQTT DEBUG] client.connect() returned: \(ok)")
    }

    // ✅ Connect with Device-ID & dynamic topics
    func connect(onMessage: @escaping (MqttMessage) -> Void,
                 onStatus: @escaping (_ connected: Bool, _ state: ConnState) -> Void,
                 for deviceId: String? = nil) {
        // Decide which deviceId we will consider "connectedDeviceId":
        if let id = deviceId, !id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            connectedDeviceId = id
            topicsToSubscribe = [
                "device/\(id)/telemetry/#",
                "device/\(id)/status",
                "device/\(id)/ack"
            ]
        } else {
            connectedDeviceId = nil
            topicsToSubscribe = []
        }

        connect(onMessage: onMessage, onStatus: onStatus)
    }

    func disconnect() {
        print("[MQTT DEBUG] disconnect() called")
        // Clear intended connected device on explicit disconnect
        connectedDeviceId = nil

        guard let client = mqtt else {
            print("[MQTT DEBUG] disconnect() -> mqtt == nil (already cleaned)")
            DispatchQueue.main.async {
                self.isConnected = false
                self.connectionState = .disconnected
                self.onStatus?(false, .disconnected)
            }
            return
        }
        client.delegate = nil
        client.disconnect()
        mqtt = nil
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionState = .disconnected
            self.onStatus?(false, .disconnected)
        }
        print("[MQTT DEBUG] disconnect() -> cleaned up")
    }

    // MARK: - Subscribe / Publish
    func subscribe(_ topic: String, qos: CocoaMQTTQoS) {
        print("[MQTT DEBUG] subscribe -> \(topic)")
        mqtt?.subscribe(topic, qos: qos)
    }

    func unsubscribe(_ topic: String) {
        print("[MQTT DEBUG] unsubscribe -> \(topic)")
        mqtt?.unsubscribe(topic)
    }

    func publishJSON(topic: String, object: [String: Any], qos: CocoaMQTTQoS = .qos1, retain: Bool = false) {
        guard let mqtt = mqtt else {
            onMessage?(MqttMessage(topic: "app/error", payload: "MQTT client nil"))
            return
        }
        guard isConnected else {
            onMessage?(MqttMessage(topic: "app/error", payload: "Nicht verbunden"))
            return
        }
        guard JSONSerialization.isValidJSONObject(object) else {
            onMessage?(MqttMessage(topic: "app/error", payload: "JSON ist ungültig"))
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

    func sendCommand(topic: String, message: String) {
        print("[MQTT DEBUG] sendCommand -> topic:\(topic) message:\(message)")
        guard let mqtt = mqtt else {
            onMessage?(MqttMessage(topic: "app/error", payload: "MQTT client nil"))
            return
        }
        guard isConnected else {
            onMessage?(MqttMessage(topic: "app/error", payload: "Nicht verbunden"))
            return
        }
        mqtt.publish(topic, withString: message, qos: .qos1, retained: false)
        onMessage?(MqttMessage(topic: topic, payload: message))
    }
}

// MARK: - CocoaMQTTDelegate
extension MqttService: CocoaMQTTDelegate {
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        let ok = (ack == .accept)
        print("[MQTT DEBUG] didConnectAck -> ack: \(ack.rawValue) (\(ack)) ok=\(ok)")
        DispatchQueue.main.async {
            self.isConnected = ok
            self.connectionState = ok ? .connected : .disconnected
            self.onStatus?(ok, self.connectionState)
        }

        if !ok {
            print("[MQTT DEBUG] didConnectAck -> connection rejected by broker (ack=\(ack.rawValue)). Likely auth/ACL/clientID issue.")
            // In case of reject, clear intended connectedDeviceId so UI doesn't assume connection
            DispatchQueue.main.async {
                self.connectedDeviceId = nil
            }
        } else {
            print("[MQTT DEBUG] didConnectAck -> accepted, auto-subscribing to topics")
            for t in topicsToSubscribe {
                print("[MQTT DEBUG] auto-subscribe -> \(t)")
                mqtt.subscribe(t, qos: .qos1)
            }
        }
    }

    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        let payloadString = message.string ?? "<binary>"
        print("[MQTT DEBUG] didReceiveMessage -> topic:\(message.topic) qos:\(message.qos) retained:\(message.retained) payload:\(payloadString)")

        // --- try to parse JSON payload into a dictionary (rawObj)
        var rawObj: [String: Any]? = nil
        if let data = payloadString.data(using: .utf8) {
            if let obj = try? JSONSerialization.jsonObject(with: data, options: []) as? [String: Any] {
                rawObj = obj
            }
        }

        // Heuristic numeric extraction (value/temperature/humidity/obstacle or plain number)
        func extractNumeric(from raw: [String: Any]?, asString s: String) -> Double? {
            if let r = raw {
                if let v = r["value"] as? Double { return v }
                if let n = r["value"] as? NSNumber { return n.doubleValue }
                if let t = r["temperature"] as? Double { return t }
                if let tS = r["temperature"] as? String, let d = Double(tS) { return d }
                if let h = r["humidity"] as? Double { return h }
                if let hS = r["humidity"] as? String, let d = Double(hS) { return d }
                if let obs = r["obstacle"] as? Bool { return obs ? 1.0 : 0.0 }
            }
            let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if let d = Double(trimmed) { return d }
            return nil
        }

        let numericValue = extractNumeric(from: rawObj, asString: payloadString)

        // Extract topicDeviceId from topic
        let topicParts = message.topic.split(separator: "/")
        let topicDeviceId: String? = topicParts.count >= 2 ? String(topicParts[1]) : nil

        // Determine reportedDeviceId from payload keys OR topicDeviceId
        let reportedDeviceId: String? = rawObj?["deviceId"] as? String
            ?? rawObj?["id"] as? String
            ?? rawObj?["devId"] as? String
            ?? rawObj?["device"] as? String
            ?? topicDeviceId

        // Keep existing onMessage behavior (topic + payload string)
        let item = MqttMessage(topic: message.topic, payload: payloadString)

        // Deliver to callback on main thread
        DispatchQueue.main.async {
            self.onMessage?(item)

            // Additionally post a Notification that DashboardDetailView / WidgetCard listen to.
            // userInfo keys: "topic" (String), "payload" (String), "raw" ([String:Any]?), "value" (Double?), "reportedDeviceId" (String?), "topicDeviceId" (String?)
            var info: [AnyHashable: Any] = [
                "topic": message.topic,
                "payload": payloadString,
                "topicDeviceId": topicDeviceId ?? "",
                "reportedDeviceId": reportedDeviceId ?? ""
            ]
            if let raw = rawObj { info["raw"] = raw }
            if let v = numericValue { info["value"] = v }
            NotificationCenter.default.post(name: .mqttTelemetryReceived, object: nil, userInfo: info)
        }
    }

    func mqtt(_ mqtt: CocoaMQTT, didDisconnectWithError err: Error?) {
        print("[MQTT DEBUG] didDisconnectWithError -> \(String(describing: err))")
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionState = .disconnected
            // Clear connectedDeviceId on unexpected disconnect as well to avoid stale UI state
            self.connectedDeviceId = nil
            self.onStatus?(false, .disconnected)
        }
    }

    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        print("[MQTT DEBUG] mqttDidDisconnect -> \(String(describing: err))")
        DispatchQueue.main.async {
            self.isConnected = false
            self.connectionState = .disconnected
            self.connectedDeviceId = nil
            self.onStatus?(false, .disconnected)
        }
    }

    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
        print("[MQTT DEBUG] didPublishMessage -> topic:\(message.topic) id:\(id)")
    }
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) { print("[MQTT DEBUG] didPublishAck -> id:\(id)") }
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) { print("[MQTT DEBUG] didSubscribeTopics -> success:\(success) failed:\(failed)") }
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) { print("[MQTT DEBUG] didUnsubscribeTopics -> \(topics)") }
    func mqttDidPing(_ mqtt: CocoaMQTT) { print("[MQTT DEBUG] ping") }
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) { print("[MQTT DEBUG] pong") }
}
