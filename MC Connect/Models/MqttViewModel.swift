//
//  MqttViewModel.swift
//  MC Connect
//
//  Created by Martin Lanius on 23.10.25.
//

import Foundation
import Combine
import CocoaMQTT

@MainActor
final class MqttViewModel: ObservableObject {
    // Status/Logs
    @Published var isConnected: Bool = false
    @Published var connectionState: ConnState = .disconnected
    @Published var messages: [MqttMessage] = []

    // Neu: letzte bekannte LED-Zustände pro Device-ID
    @Published private(set) var lastLedStateByDevice: [String: Bool] = [:]

    // ✅ Neu: aktuell verbundene Device-ID
    @Published private(set) var connectedDeviceId: String?

    private let service: MqttServiceType

    init(service: MqttServiceType) {
        self.service = service
        print("MqttViewModel init with service: \(type(of: service))")
    }

    // MARK: - Connection lifecycle

    func autoConnectOnAppear() {
        connect()
    }

    /// Connect — optional mit Device-ID (wird in connectedDeviceId gespeichert)
    func connect(for deviceId: String? = nil) {
        print("🔌 MqttViewModel.connect(for: \(deviceId ?? "nil")) — starting")
        connectedDeviceId = deviceId

        service.connect(onMessage: { [weak self] msg in
            // service callback may be called off-main; marshal to main actor
            Task { @MainActor in
                self?.append(msg)
            }
        }, onStatus: { [weak self] connected, state in
            // marshal UI updates to main actor
            Task { @MainActor in
                print("📡 service onStatus -> connected: \(connected), state: \(state)")
                self?.isConnected = connected
                self?.connectionState = state
            }
        })
    }

    func disconnect() {
        print("🔌 MqttViewModel.disconnect()")
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

    func setConfig(host: String, port: Int, clientID: String, username: String, password: String) {
        print("🔧 setConfig -> host:\(host) port:\(port) clientID:\(clientID) username:\(username)")
        service.setConfig(host: host, port: port, clientID: clientID, username: username, password: password)
    }

    // MARK: - Helpers

    func lastKnownLedState(for id: String) -> Bool? {
        lastLedStateByDevice[id]
    }

    /// Prüft, ob ViewModel aktuell eine Verbindung hat und optional, ob sie zu diesem device gehört.
    func isConnectedFor(device: Device) -> Bool {
        guard isConnected else { return false }
        if let cid = connectedDeviceId {
            return cid == device.id
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

        // Versuche, LED-State aus Nachricht zu extrahieren (robustere Behandlung)
        do {
            if msg.topic.contains("telemetry") || msg.topic.contains("ack") || msg.topic.contains("status") {
                if let data = msg.payload.data(using: .utf8),
                   let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {

                    // Versuche verschiedene Felder zu lesen
                    var ledState: Bool? = nil

                    if let valueInt = json["value"] as? Int {
                        ledState = (valueInt == 1)
                    } else if let valueBool = json["value"] as? Bool {
                        ledState = valueBool
                    } else if let status = json["status"] as? String {
                        let s = status.lowercased()
                        if s == "on" || s == "1" || s == "true" {
                            ledState = true
                        } else if s == "off" || s == "0" || s == "false" {
                            ledState = false
                        }
                    } else if let target = json["target"] as? String, target == "led", json["value"] == nil {
                        // maybe payload uses {"target":"led","status":"on"}
                        if let status = json["status"] as? String {
                            ledState = (status.lowercased() == "on")
                        }
                    }

                    if let isOn = ledState {
                        // Heuristik: versuche Device-ID aus Topic zu extrahieren
                        let deviceIdFromTopic = extractDeviceId(from: msg.topic)
                        let deviceId = deviceIdFromTopic ?? connectedDeviceId ?? "default"
                        print("🔍 LED state parsed (\(isOn)) for deviceId: \(deviceId) (topic: \(msg.topic))")
                        lastLedStateByDevice[deviceId] = isOn
                    }
                }
            }
        } catch {
            print("⚠️ Error parsing MQTT payload: \(error)")
        }
    }

    /// Einfache Heuristik, um eine Device-ID aus einem Topic wie "device/<id>/telemetry" zu extrahieren.
    private func extractDeviceId(from topic: String) -> String? {
        let comps = topic.split(separator: "/").map { String($0) }
        // Falls Format "device/<id>/..." -> return <id>
        if comps.count >= 2 {
            if comps[0].lowercased() == "device" {
                return comps[1]
            }
            // Alternativ: wenn erstes Element nicht generisch (z.B. "pi", "device") return first as id?
            // Vorsichtig: das ist heuristisch; wir versuchen eher "device/<id>" Pattern
        }
        return nil
    }
}
