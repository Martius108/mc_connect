//
//  MqttService.swift
//  MC_Connect
//
//  Created by Martin Lanius on 09.11.25.
//

import Foundation
import Combine
import CocoaMQTT

// Protocol for MQTT Service to allow for testing and different implementations
protocol MqttServiceProtocol {
    var connectionState: CurrentValueSubject<MqttConnectionState, Never> { get }
    var receivedMessages: PassthroughSubject<MqttMessage, Never> { get }
    
    func connect(config: MqttConfiguration) -> Bool
    func disconnect()
    func subscribe(to topics: [String], qos: Int) -> Bool
    func unsubscribe(from topics: [String]) -> Bool
    func publish(topic: String, payload: String, qos: Int) -> Bool
}

// MQTT Service Implementation using CocoaMQTT
class MqttService: MqttServiceProtocol, ObservableObject {
    var connectionState = CurrentValueSubject<MqttConnectionState, Never>(.disconnected)
    var receivedMessages = PassthroughSubject<MqttMessage, Never>()
    
    private var mqttClient: CocoaMQTT?
    private var configuration: MqttConfiguration?
    private var subscribedTopics: Set<String> = []
    
    init() {
        // Initialize MQTT client will be created on connect
    }
    
    func connect(config: MqttConfiguration) -> Bool {
        guard !config.host.isEmpty else {
            connectionState.send(.error("Host cannot be empty"))
            return false
        }
        
        // IMPORTANT: If already connected with the same configuration, don't reconnect
        // This prevents unnecessary disconnection/reconnection cycles when switching tabs
        if mqttClient != nil,
           case .connected = connectionState.value,
           let existingConfig = configuration,
           existingConfig.host == config.host &&
           existingConfig.port == config.port &&
           existingConfig.username == config.username &&
           existingConfig.password == config.password {
            // Already connected with same settings - nothing to do
            return true
        }
        
        // Disconnect existing connection if any (different config or not connected)
        if let existingClient = mqttClient {
            existingClient.disconnect()
            // Clear subscribed topics when disconnecting
            subscribedTopics.removeAll()
        }
        
        configuration = config
        connectionState.send(.connecting)
        
        // Create CocoaMQTT client
        let mqtt = CocoaMQTT(clientID: config.clientId, host: config.host, port: UInt16(config.port))
        mqtt.username = config.username
        mqtt.password = config.password
        mqtt.keepAlive = UInt16(config.keepAlive)
        mqtt.cleanSession = config.cleanSession // This should clear all subscriptions on reconnect
        mqtt.delegate = self
        
        self.mqttClient = mqtt
        
        // Connect
        let connected = mqtt.connect()
        if !connected {
            connectionState.send(.error("Failed to initiate connection"))
            return false
        }
        
        return true
    }
    
    func disconnect() {
        mqttClient?.disconnect()
        mqttClient = nil
        subscribedTopics.removeAll()
        connectionState.send(.disconnected)
    }
    
    func subscribe(to topics: [String], qos: Int = 0) -> Bool {
        guard let mqtt = mqttClient,
              case .connected = connectionState.value else {
            return false
        }
        
        // Use QoS 1 for better message delivery guarantee (at least once delivery)
        // This ensures messages are not lost even with high message rates
        let effectiveQoS = max(qos, 1) // Minimum QoS 1 for subscriptions
        let mqttQoS = CocoaMQTTQoS(rawValue: UInt8(effectiveQoS)) ?? .qos1
        
        for topic in topics {
            mqtt.subscribe(topic, qos: mqttQoS)
            subscribedTopics.insert(topic)
        }
        
        return true
    }
    
    func unsubscribe(from topics: [String]) -> Bool {
        guard let mqtt = mqttClient,
              case .connected = connectionState.value else {
            return false
        }
        
        for topic in topics {
            mqtt.unsubscribe(topic)
            subscribedTopics.remove(topic)
        }
        
        return true
    }
    
    func publish(topic: String, payload: String, qos: Int = 0) -> Bool {
        guard let mqtt = mqttClient,
              case .connected = connectionState.value else {
            return false
        }
        
        let mqttQoS = CocoaMQTTQoS(rawValue: UInt8(qos)) ?? .qos0
        mqtt.publish(topic, withString: payload, qos: mqttQoS)
        
        return true
    }
}

// MARK: - CocoaMQTTDelegate
extension MqttService: CocoaMQTTDelegate {
    func mqtt(_ mqtt: CocoaMQTT, didConnectAck ack: CocoaMQTTConnAck) {
        if ack == .accept {
            connectionState.send(.connected)
        } else {
            let errorMsg = "Connection rejected: \(ack)"
            connectionState.send(.error(errorMsg))
        }
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishMessage message: CocoaMQTTMessage, id: UInt16) {
        // Message published successfully
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didPublishAck id: UInt16) {
        // Publish acknowledged
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didReceiveMessage message: CocoaMQTTMessage, id: UInt16) {
        let payload = message.string ?? ""
        
        let mqttMessage = MqttMessage(topic: message.topic, payload: payload, qos: Int(message.qos.rawValue))
        
        // Send message directly to Combine publisher
        // Since devices now send at proper intervals, we don't need complex buffering
        receivedMessages.send(mqttMessage)
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didSubscribeTopics success: NSDictionary, failed: [String]) {
        // Subscription handled
    }
    
    func mqtt(_ mqtt: CocoaMQTT, didUnsubscribeTopics topics: [String]) {
        // Unsubscription successful
    }
    
    func mqttDidPing(_ mqtt: CocoaMQTT) {
        // Ping sent
    }
    
    func mqttDidReceivePong(_ mqtt: CocoaMQTT) {
        // Pong received
    }
    
    func mqttDidDisconnect(_ mqtt: CocoaMQTT, withError err: Error?) {
        if let error = err {
            connectionState.send(.error(error.localizedDescription))
        } else {
            connectionState.send(.disconnected)
        }
        // Clear subscribed topics on disconnect
        subscribedTopics.removeAll()
    }
}

