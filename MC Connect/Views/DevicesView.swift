//
//  DevicesView.swift
//  MC Connect
//
//  Created by Martin Lanius on 25.10.25.
//

import SwiftUI
import SwiftData

struct DevicesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var devices: [Device]
    @EnvironmentObject var mqtt: MqttViewModel

    @State private var showingAddSheet = false

    // Track which device is currently in the process of connecting
    @State private var connectingDeviceId: String? = nil
    @State private var lastConnectError: String? = nil

    var body: some View {
        NavigationView {
            List {
                ForEach(devices) { device in
                    HStack {
                        NavigationLink(destination: DeviceDetailView(device: device)) {
                            VStack(alignment: .leading) {
                                Text(device.name)
                                    .font(.headline)
                                Text(device.type)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }

                        Spacer()

                        // Use device.externalId as effectiveId (now always non-optional)
                        let effectiveId = device.externalId

                        // Connected state for this device: compare mqtt.connectedDeviceId with effectiveId
                        let isConnectedForThisDevice = mqtt.isConnected && mqtt.connectedDeviceId == effectiveId
                        let isConnectingForThisDevice = connectingDeviceId == effectiveId

                        HStack(spacing: 8) {
                            // Status dot / progress
                            if isConnectedForThisDevice {
                                Circle().foregroundColor(.green).frame(width: 10, height: 10)
                            } else if isConnectingForThisDevice {
                                ProgressView().scaleEffect(0.5)
                            } else {
                                Circle().foregroundColor(.red).frame(width: 10, height: 10)
                            }

                            // Connect / Disconnect button
                            Button {
                                Task {
                                    if isConnectedForThisDevice {
                                        // Disconnect if currently connected to this device
                                        mqtt.disconnect()
                                        // Clear any per-device connecting state
                                        connectingDeviceId = nil
                                    } else {
                                        // Start connection sequence for this device
                                        await connectToDevice(device)
                                    }
                                }
                            } label: {
                                Text(isConnectedForThisDevice ? "Disconnect" : (isConnectingForThisDevice ? "Connecting…" : "Connect"))
                                    .font(.subheadline)
                            }
                            .buttonStyle(.bordered)
                        }
                        .frame(minWidth: 120, alignment: .trailing)
                    }
                    .padding(.vertical, 6)
                }
                .onDelete(perform: deleteDevices)
            }
            .navigationTitle("Devices")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: {
                        showingAddSheet = true
                    }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddSheet) {
                DeviceInputView(
                    onSave: { device in
                        // Bestimme existierende Devices direkt via modelContext
                        let fetchDesc = FetchDescriptor<Device>()
                        var existingCount = 0
                        do {
                            let existing = try modelContext.fetch(fetchDesc)
                            existingCount = existing.count
                        } catch {
                            existingCount = devices.count // fallback
                        }

                        // Wenn dies das erste Device ist, markiere es als active
                        if existingCount == 0 {
                            device.isActive = true
                        }

                        modelContext.insert(device)
                        do {
                            try modelContext.save()
                            print("[DevicesView] Device saved: \(device.id)")
                        } catch {
                            print("[DevicesView] Fehler beim Speichern des Geräts:", error)
                        }
                    },
                    onCreate: { device in
                        // Optional: wenn du unterschiedliche Logik bei Erstellung brauchst.
                    }
                )
            }
        }
    }

    private func deleteDevices(offsets: IndexSet) {
        for index in offsets {
            let device = devices[index]
            modelContext.delete(device)
        }
        do {
            try modelContext.save()
        } catch {
            print("Fehler beim Löschen des Geräts:", error)
        }
    }

    // MARK: - Connection helper

    @MainActor
    private func connectToDevice(_ device: Device, forceReconnect: Bool = false) async {
        // Use device.externalId as effectiveId (now always non-optional)
        let effectiveId = device.externalId

        // If already connected to this effectiveId and not forcing, nothing to do
        if !forceReconnect, mqtt.isConnected, mqtt.connectedDeviceId == effectiveId {
            print("[DevicesView] Already connected to \(effectiveId)")
            return
        }

        // Set connecting indicator
        connectingDeviceId = effectiveId
        lastConnectError = nil

        // Configure MQTT with device broker info
        mqtt.setConfig(
            host: device.host,
            port: device.port,
            clientID: device.clientID,
            username: device.username,
            password: device.password
        )

        // Topics to subscribe for this device
        let topicsToSubscribe = [
            "device/\(effectiveId)/telemetry/#",
            "device/\(effectiveId)/status",
            "device/\(effectiveId)/ack"
        ]
        print("[DevicesView] Connecting for effectiveId=\(effectiveId) with topics \(topicsToSubscribe)")

        // Start the connection (non-blocking)
        mqtt.connect(for: effectiveId, subscribeTo: topicsToSubscribe)

        // Wait for connection (polling with timeout)
        let timeoutSeconds: Double = 5.0
        let pollInterval: Double = 0.1
        var elapsed: Double = 0

        while !mqtt.isConnected && elapsed < timeoutSeconds {
            try? await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
            elapsed += pollInterval
        }

        if mqtt.isConnected && mqtt.connectedDeviceId == effectiveId {
            print("[DevicesView] Connected to \(effectiveId)")
            lastConnectError = nil
        } else {
            print("[DevicesView] Failed to connect to \(effectiveId)")
            lastConnectError = "Verbindung nicht hergestellt"
        }

        // Clear connecting indicator (if still connecting for this device)
        if connectingDeviceId == effectiveId {
            connectingDeviceId = nil
        }
    }
}
