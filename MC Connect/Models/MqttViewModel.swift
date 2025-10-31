//
//  MqttViewModel.swift
//  MC Connect
//
//  Created by Martin Lanius on 23.10.25.
//

import Foundation
import Combine
import CocoaMQTT

// Central notification name to avoid literal typos across the app
extension Notification.Name {
    static let mqttTelemetryReceived = Notification.Name("mqttTelemetryReceived")
}

@MainActor
final class MqttViewModel: ObservableObject {
    // Status/Logs
    @Published var isConnected: Bool = false
    @Published var connectionState: ConnState = .disconnected
    @Published var messages: [MqttMessage] = []

    // Neu: letzte bekannte LED-Zustände pro Device-externalId
    @Published private(set) var lastLedStateByDevice: [String: Bool] = [:]

    // Neu: aktuell verbundene Device-externalId
    @Published private(set) var connectedDeviceId: String?

    private let service: MqttServiceType

    // Pending topics that should be subscribed once the connection is established
    private var pendingSubscribeTopics: [String] = []

    init(service: MqttServiceType) {
        self.service = service
        print("MqttViewModel init with service: \(type(of: service))")
    }

    // MARK: - Connection lifecycle

    func autoConnectOnAppear() {
        connect()
    }

    /// Connect — optional mit deviceExternalId (wird in connectedDeviceId gespeichert)
    /// Wenn möglich wird die concrete Service-Variante `connect(..., for:)` genutzt,
    /// damit der Service bereits beim Verbindungsaufbau die richtigen Topics/Subscribes setzen kann.
    func connect(for deviceId: String? = nil) {
        print("🔌 MqttViewModel.connect(for: \(deviceId ?? "nil")) — starting")
        connectedDeviceId = deviceId

        let onMessageCallback: (MqttMessage) -> Void = { [weak self] msg in
            Task { @MainActor in
                self?.append(msg)
            }
        }

        let onStatusCallback: (_ connected: Bool, _ state: ConnState) -> Void = { [weak self] connected, state in
            Task { @MainActor in
                guard let self = self else { return }
                print("📡 service onStatus -> connected: \(connected), state: \(state)")
                self.isConnected = connected
                self.connectionState = state

                // If connection established, apply any pending subscribes
                if connected && !self.pendingSubscribeTopics.isEmpty {
                    print("MQTT: connection established, subscribing pending topics: \(self.pendingSubscribeTopics)")
                    for t in self.pendingSubscribeTopics {
                        self.subscribe(topic: t)
                    }
                    self.pendingSubscribeTopics.removeAll()
                }
            }
        }

        // Prefer to call the service variant that accepts a deviceId if the concrete service supports it.
        if let concrete = service as? MqttService {
            concrete.connect(onMessage: onMessageCallback, onStatus: onStatusCallback, for: deviceId)
        } else {
            // Fallback to protocol method (service must implement connect(onMessage:onStatus:))
            service.connect(onMessage: onMessageCallback, onStatus: onStatusCallback)
        }
    }

    /// Connect and request subscription to topics after successful ConnAck.
    func connect(for deviceId: String? = nil, subscribeTo topics: [String]) {
        // store pending topics first so onStatus can pick them up
        self.pendingSubscribeTopics = topics.filter { !$0.isEmpty }
        connect(for: deviceId)
    }

    func disconnect() {
        print("🔌 MqttViewModel.disconnect()")
        // clear pending topics when disconnecting
        pendingSubscribeTopics.removeAll()
        service.disconnect()
        // ensure published change is on main actor
        Task { @MainActor in
            self.connectedDeviceId = nil
            self.isConnected = false
            self.connectionState = .disconnected
        }
    }

    // MARK: - Publish / Subscribe wrappers (mit Logging)

    func publish(topic: String, json: [String: Any],
                 qos: CocoaMQTTQoS = .qos1, retain: Bool = false) {
        print("📤 publish -> topic: \(topic), json: \(json)")
        service.publishJSON(topic: topic, object: json, qos: qos, retain: retain)
    }

    func publishAsync(topic: String, json: [String: Any]) async {
        print("📤 publishAsync -> topic: \(topic), json: \(json)")
        service.publishJSON(topic: topic, object: json, qos: .qos1, retain: false)
    }

    func subscribe(topic: String, qos: CocoaMQTTQoS = .qos1) {
        print("🔔 subscribe -> \(topic)")
        service.subscribe(topic, qos: qos)
    }

    func unsubscribe(topic: String) {
        print("🔕 unsubscribe -> \(topic)")
        service.unsubscribe(topic)
    }

    func sendCommand(topic: String, message: String) {
        print("➡️ sendCommand -> topic: \(topic), message: \(message)")
        service.sendCommand(topic: topic, message: message)
    }

    /// Set config explicitly (old method kept)
    func setConfig(host: String, port: Int, clientID: String, username: String, password: String) {
        print("🔧 setConfig -> host:\(host) port:\(port) clientID:\(clientID) username:\(username)")
        service.setConfig(host: host, port: port, clientID: clientID, username: username, password: password)
    }

    /// New helper: use the clientID provided by the underlying service implementation (if available)
    func setConfigUsingServiceClientID(host: String, port: Int, username: String, password: String) {
        // Try to read clientID from concrete service (safe fallback if unavailable)
        var clientIdToUse = "ios-\(UUID().uuidString.prefix(8))"
        if let concrete = service as? MqttService {
            clientIdToUse = concrete.clientID
        } else if let svcWithClient = (service as AnyObject).value(forKey: "clientID") as? String {
            clientIdToUse = svcWithClient
        }
        print("🔧 setConfigUsingServiceClientID -> host:\(host) port:\(port) clientID:\(clientIdToUse) username:\(username)")
        // <-- hier port als Int übergeben (kein UInt16-Cast)
        service.setConfig(host: host, port: port, clientID: clientIdToUse, username: username, password: password)
    }

    // MARK: - Helpers

    func lastKnownLedState(for id: String) -> Bool? {
        lastLedStateByDevice[id]
    }

    /// Prüft, ob ViewModel aktuell eine Verbindung hat und optional, ob sie zu diesem device (externalId) gehört.
    func isConnectedFor(device: Device) -> Bool {
        guard isConnected else { return false }
        if let cid = connectedDeviceId {
            // compare with externalId (device.externalId) — not internal id
            return cid == device.externalId
        }
        return isConnected
    }

    // MARK: - Internals

    private func append(_ msg: MqttMessage) {
        // Ensure modifications happen on main actor (class is @MainActor, so we're good)
        print("📥 Received MQTT message -> topic: \(msg.topic), payload: \(msg.payload)")

        // Append to message log (keep bounded size)
        messages.append(msg)
        if messages.count > 500 {
            messages.removeFirst(messages.count - 500)
        }

        // Robust parsing: try JSON (allow fragments), otherwise fallback to plain string
        if let data = msg.payload.data(using: .utf8) {
            do {
                let jsonAny = try JSONSerialization.jsonObject(with: data, options: .allowFragments)
                // jsonAny can be Dictionary, Array, String, Number, Bool, etc.
                print("📗 parsed payload (allowFragments): \(jsonAny)")

                // If it's a dictionary, try to extract telemetry fields (pin/value/obstacle/status/target)
                if let dict = jsonAny as? [String: Any] {
                    handleTelemetryDict(topic: msg.topic, dict: dict)
                } else if let arr = jsonAny as? [Any] {
                    // Received an array — post as-is
                    postTelemetryNotification(["topic": msg.topic, "payload": arr])
                } else if let str = jsonAny as? String {
                    // simple string payload like "offline" / "online"
                    postTelemetryNotification(["topic": msg.topic, "payload": str])
                } else if let num = jsonAny as? NSNumber {
                    postTelemetryNotification(["topic": msg.topic, "payload": num])
                } else {
                    // Unknown type — still forward raw string
                    postTelemetryNotification(["topic": msg.topic, "payload": msg.payload])
                }
            } catch {
                // JSON parse failed even with allowFragments: fallback to plain string
                print("⚠️ Error parsing MQTT payload (allowFragments): \(error). Falling back to string.")
                postTelemetryNotification(["topic": msg.topic, "payload": msg.payload])
            }
        } else {
            // payload couldn't be converted to data — forward raw
            postTelemetryNotification(["topic": msg.topic, "payload": msg.payload])
        }
    }

    /// Versucht, typische Telemetrie-Felder zu extrahieren und postet eine Notification.
    private func handleTelemetryDict(topic: String, dict: [String: Any]) {
        print("🔎 handleTelemetryDict for topic: \(topic) dict: \(dict)")

        // LED-state detection (robuster)
        var ledState: Bool? = nil
        if let valueInt = dict["value"] as? Int {
            ledState = (valueInt == 1)
        } else if let valueBool = dict["value"] as? Bool {
            ledState = valueBool
        } else if let valueStr = dict["value"] as? String {
            let s = valueStr.lowercased()
            if s == "1" || s == "true" || s == "on" { ledState = true }
            else if s == "0" || s == "false" || s == "off" { ledState = false }
        } else if let status = dict["status"] as? String {
            let s = status.lowercased()
            if s == "on" || s == "1" || s == "true" { ledState = true }
            else if s == "off" || s == "0" || s == "false" { ledState = false }
        } else if let target = dict["target"] as? String, (target.lowercased() == "led" || target.lowercased() == "led_ext") {
            // sometimes payload uses status field instead of value
            if let status = dict["status"] as? String {
                let s = status.lowercased()
                if s == "on" || s == "1" || s == "true" { ledState = true }
                else if s == "off" || s == "0" || s == "false" { ledState = false }
            }
        }

        if let isOn = ledState {
            let deviceIdFromTopic = extractDeviceId(from: topic)
            // Prefer the topic-extracted id; fall back to currently intended connectedDeviceId
            let deviceId = deviceIdFromTopic ?? connectedDeviceId ?? "default"
            print("🔍 LED state parsed (\(isOn)) for deviceId: \(deviceId) (topic: \(topic))")
            lastLedStateByDevice[deviceId] = isOn
        }

        // Telemetry specific: pin/value/obstacle
        var pin: Int? = nil
        if let p = dict["pin"] as? Int {
            pin = p
        } else if let pStr = dict["pin"] as? String, let p = Int(pStr) {
            pin = p
        }

        var value: Double? = nil
        if let obstacle = dict["obstacle"] as? Bool {
            value = obstacle ? 1.0 : 0.0
        } else if let vDouble = dict["value"] as? Double {
            value = vDouble
        } else if let vInt = dict["value"] as? Int {
            value = Double(vInt)
        } else if let vStr = dict["value"] as? String, let v = Double(vStr) {
            value = v
        } else if let stateInt = dict["state"] as? Int {
            value = Double(stateInt)
        }

        // Post a Notification with extracted fields (if any) plus raw dict
        var userInfo: [String: Any] = ["topic": topic, "raw": dict]
        if let p = pin { userInfo["pin"] = p }
        if let v = value { userInfo["value"] = v }
        if let ls = ledState { userInfo["led_state"] = ls }

        postTelemetryNotification(userInfo)
    }

    /// Einfache Heuristik, um eine Device-externalId aus einem Topic wie "device/<id>/telemetry" zu extrahieren.
    private func extractDeviceId(from topic: String) -> String? {
        let comps = topic.split(separator: "/").map { String($0) }
        // Falls Format "device/<id>/..." -> return <id>
        if comps.count >= 2 {
            if comps[0].lowercased() == "device" {
                return comps[1]
            }
        }
        return nil
    }

    // MARK: - Notification helper

    /// Post telemetry notification always on main thread and log keys for debugging.
    private func postTelemetryNotification(_ userInfo: [String: Any]) {
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .mqttTelemetryReceived,
                                            object: nil,
                                            userInfo: userInfo)
            #if DEBUG
            print("🔔 MqttViewModel posted \(Notification.Name.mqttTelemetryReceived.rawValue) -> keys: \(Array(userInfo.keys))")
            #endif
        }
    }
}
