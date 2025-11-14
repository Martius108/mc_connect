//
//  DevicesView.swift
//  MC_Connect
//
//  Created by Martin Lanius on 09.11.25.
//

import SwiftUI
import SwiftData

struct DevicesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Device.name) private var devices: [Device]
    @State private var showingAddDevice = false
    @State private var showingEditDevice: Device?
    @EnvironmentObject var mqttViewModel: MqttViewModel
    @State private var refreshID = UUID()
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(devices) { device in
                    DeviceRow(device: device)
                        .id("\(device.id)-\(device.isOnline)-\(device.lastSeen?.timeIntervalSince1970 ?? 0)-\(refreshID)")
                        .contextMenu {
                            Button {
                                showingEditDevice = device
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            
                            Button(role: .destructive) {
                                deleteDevice(device)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                .onDelete(perform: deleteDevices)
            }
            .navigationTitle("Devices")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddDevice = true
                    } label: {
                        Label("Add Device", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddDevice) {
                AddDeviceView()
                    .environmentObject(mqttViewModel)
            }
            .sheet(item: $showingEditDevice) { device in
                EditDeviceView(device: device)
                    .environmentObject(mqttViewModel)
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("DeviceStatusUpdated"))) { _ in
                refreshID = UUID()
            }
        }
    }
    
    private func deleteDevices(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                let device = devices[index]
                // Unsubscribe from MQTT topics before deleting
                mqttViewModel.unsubscribeFromDeviceTelemetry(deviceId: device.id)
                modelContext.delete(device)
            }
            
            // Reconnect MQTT to refresh subscriptions with remaining devices
            reconnectMQTTAfterDeviceDeletion()
        }
    }
    
    private func deleteDevice(_ device: Device) {
        withAnimation {
            // Unsubscribe from MQTT topics before deleting
            mqttViewModel.unsubscribeFromDeviceTelemetry(deviceId: device.id)
            modelContext.delete(device)
            
            // Reconnect MQTT to refresh subscriptions with remaining devices
            // This ensures the service is restarted without the deleted device
            reconnectMQTTAfterDeviceDeletion()
        }
    }
    
    private func reconnectMQTTAfterDeviceDeletion() {
        // Only reconnect if currently connected
        if case .connected = mqttViewModel.connectionState {
            mqttViewModel.disconnect()
            // Wait a bit for disconnection to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // Notify DashboardDetailView to reconnect
                // The DashboardDetailView manages the MQTT connection
                NotificationCenter.default.post(name: NSNotification.Name("ReconnectMQTT"), object: nil)
            }
        }
    }
}

struct DeviceRow: View {
    let device: Device
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(device.name)
                    .font(.headline)
                Text(device.type)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                StatusIndicator(isOnline: device.isOnline)
                if let lastSeen = device.lastSeen {
                    Text("Last seen: \(lastSeen, style: .relative)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                } else {
                    Text("Never")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct AddDeviceView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var mqttViewModel: MqttViewModel
    @Query private var telemetryConfigs: [TelemetryConfig]
    
    @State private var name: String = ""
    @State private var deviceId: String = ""
    @State private var selectedType: String = "ESP32"
    
    let deviceTypes = ["ESP32", "ESP8266", "Pi Pico 2W", "Pi Zero 2W", "Arduino", "Other"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Device Information") {
                    TextField("Device Name", text: $name)
                        .onSubmit { hideKeyboard() }
                    TextField("Device ID", text: $deviceId)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onSubmit { hideKeyboard() }
                    
                    Picker("Device Type", selection: $selectedType) {
                        ForEach(deviceTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                }
            }
            .navigationTitle("Add Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        hideKeyboard()
                        saveDevice()
                    }
                    .disabled(name.isEmpty || deviceId.isEmpty)
                }
            }
        }
    }
    
    private func saveDevice() {
        let device = Device(id: deviceId, name: name, type: selectedType)
        modelContext.insert(device)
        
        // Save the context to ensure the device is persisted before reconnecting
        try? modelContext.save()
        
        // Notify DashboardDetailView to reconnect MQTT
        // This ensures the new device is subscribed along with all other devices
        // The DashboardDetailView manages the MQTT connection
        // Use a small delay to ensure SwiftData has processed the insert
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            NotificationCenter.default.post(name: NSNotification.Name("ReconnectMQTT"), object: nil)
        }
        
        dismiss()
    }
}

struct EditDeviceView: View {
    let device: Device
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var mqttViewModel: MqttViewModel
    @Query private var telemetryConfigs: [TelemetryConfig]
    
    @State private var name: String = ""
    @State private var deviceId: String = ""
    @State private var selectedType: String = "ESP32"
    
    let deviceTypes = ["ESP32", "ESP8266", "Pi Pico 2W", "Pi Zero 2W", "Arduino", "Other"]
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Device Information") {
                    TextField("Device Name", text: $name)
                        .onSubmit { hideKeyboard() }
                    TextField("Device ID", text: $deviceId)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onSubmit { hideKeyboard() }
                        .disabled(true) // Device ID should not be changed
                    
                    Picker("Device Type", selection: $selectedType) {
                        ForEach(deviceTypes, id: \.self) { type in
                            Text(type).tag(type)
                        }
                    }
                }
            }
            .navigationTitle("Edit Device")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        hideKeyboard()
                        saveDevice()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .onAppear {
                name = device.name
                deviceId = device.id
                selectedType = device.type
            }
        }
    }
    
    private func saveDevice() {
        device.name = name
        device.type = selectedType
        dismiss()
    }
}

struct StatusIndicator: View {
    let isOnline: Bool
    
    var body: some View {
        Circle()
            .fill(isOnline ? Color.green : Color.gray)
            .frame(width: 12, height: 12)
    }
}
