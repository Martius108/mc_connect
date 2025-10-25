//
//  MqttViewModel.swift
//  MC Connect
//
//  Created by Martin Lanius on 23.10.25.
//

import Foundation
import Combine
import CocoaMQTT

final class MqttViewModel: ObservableObject {
    // Status/Logs
    @Published var isConnected: Bool = false
    @Published var connectionState: ConnState = .disconnected
    @Published var messages: [MqttMessage] = []

    private let service: MqttServiceType

    init(service: MqttServiceType) {
        self.service = service
    }

    func autoConnectOnAppear() {
        connect()
    }

    func connect() {
        service.connect(onMessage: { [weak self] msg in
            self?.append(msg)
        }, onStatus: { [weak self] connected, state in
            DispatchQueue.main.async {
                self?.isConnected = connected
                self?.connectionState = state
            }
        })
    }

    func disconnect() {
        service.disconnect()
    }

    func publish(topic: String, json: [String: Any],
                 qos: CocoaMQTTQoS = .qos1, retain: Bool = false) {
        service.publishJSON(topic: topic, object: json, qos: qos, retain: retain)
    }

    func subscribe(topic: String, qos: CocoaMQTTQoS = .qos1) {
        service.subscribe(topic, qos: qos)
    }

    func unsubscribe(topic: String) {
        service.unsubscribe(topic)
    }

    private func append(_ msg: MqttMessage) {
        messages.append(msg)
        if messages.count > 500 { messages.removeFirst(messages.count - 500) }
    }
}
