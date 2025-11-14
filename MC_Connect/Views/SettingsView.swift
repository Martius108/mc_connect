//
//  SettingsView.swift
//  MC_Connect
//
//  Created by Martin Lanius on 09.11.25.
//

import SwiftUI
import SwiftData

extension View {
    func hideKeyboard() {
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
    }
}

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var brokerSettings: [BrokerSettings]
    @Query private var telemetryConfigs: [TelemetryConfig]
    @EnvironmentObject var mqttViewModel: MqttViewModel
    
    @State private var host: String = ""
    @State private var port: String = "1883"
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var clientId: String = ""
    @State private var keepAlive: String = "60"
    @State private var telemetryKeywords: [String] = []
    @State private var keywordUnits: [String: String] = [:]
    @State private var newKeyword: String = ""
    @State private var newKeywordUnit: String = ""
    
    var body: some View {
        NavigationStack {
            Form {
                Section("MQTT Broker Settings") {
                    TextField("Host", text: $host)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onSubmit { hideKeyboard() }
                    TextField("Port", text: $port)
                        .keyboardType(.numberPad)
                        .onSubmit { hideKeyboard() }
                    TextField("Username (optional)", text: $username)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onSubmit { hideKeyboard() }
                    SecureField("Password (optional)", text: $password)
                        .onSubmit { hideKeyboard() }
                    TextField("Client ID (optional)", text: $clientId)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .onSubmit { hideKeyboard() }
                    TextField("Keep Alive (seconds)", text: $keepAlive)
                        .keyboardType(.numberPad)
                        .onSubmit { hideKeyboard() }
                    
                    Button(action: {
                        hideKeyboard()
                        saveBrokerSettings()
                    }) {
                        HStack {
                            Spacer()
                            Text("Save MQTT Settings")
                            Spacer()
                        }
                    }
                    .disabled(!isValidConfiguration)
                }
                
                Section("Telemetry Keywords") {
                    // List of existing keywords
                    ForEach(telemetryKeywords, id: \.self) { keyword in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(keyword)
                                    .font(.body)
                                if let unit = keywordUnits[keyword], !unit.isEmpty {
                                    Text("Unit: \(unit)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            Spacer()
                            Button(role: .destructive) {
                                deleteKeyword(keyword)
                            } label: {
                                Image(systemName: "trash")
                            }
                        }
                    }
                    
                    // Quick add standard keywords
                    let availableQuickKeywords = TelemetryKeyword.allCases.filter { !telemetryKeywords.contains($0.rawValue) }
                    if !availableQuickKeywords.isEmpty {
                        Text("Quick Add Standard Keywords:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 4)
                        
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100))], spacing: 8) {
                            ForEach(availableQuickKeywords, id: \.rawValue) { enumKeyword in
                                Button {
                                    addQuickKeyword(enumKeyword.rawValue, unit: enumKeyword.unit)
                                } label: {
                                    Text(enumKeyword.displayName)
                                        .font(.caption)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(6)
                                }
                            }
                        }
                    }
                    
                    // Add custom keyword
                    VStack(spacing: 8) {
                        Text("Add Custom Keyword:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        
                        HStack(spacing: 8) {
                            TextField("Name", text: $newKeyword)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .onSubmit { hideKeyboard() }
                            TextField("Unit (optional)", text: $newKeywordUnit)
                                .autocapitalization(.none)
                                .disableAutocorrection(true)
                                .onSubmit { hideKeyboard() }
                        }
                        
                        Button("Save Keyword") {
                            hideKeyboard()
                            addKeyword()
                            saveKeywords()
                        }
                        .disabled(newKeyword.isEmpty)
                    }
                }
                
                Section("Connection Status") {
                    ConnectionStatusView()
                }
                
                Section("MQTT Payload Log") {
                    if mqttViewModel.recentPayloads.isEmpty {
                        Text("No messages received yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ScrollViewReader { proxy in
                            ScrollView {
                                VStack(alignment: .leading, spacing: 8) {
                                    ForEach(mqttViewModel.recentPayloads) { entry in
                                        PayloadLogRow(entry: entry)
                                            .id(entry.id)
                                    }
                                }
                            }
                            .frame(maxHeight: 200)
                            .onAppear {
                                // Scroll to top when view appears
                                if let firstEntry = mqttViewModel.recentPayloads.first {
                                    proxy.scrollTo(firstEntry.id, anchor: .top)
                                }
                            }
                            .onChange(of: mqttViewModel.recentPayloads.count) { _, _ in
                                // Scroll to top when new entries are added
                                if let firstEntry = mqttViewModel.recentPayloads.first {
                                    withAnimation {
                                        proxy.scrollTo(firstEntry.id, anchor: .top)
                                    }
                                }
                            }
                        }
                        
                        Button("Clear Log") {
                            mqttViewModel.clearLog()
                        }
                        .font(.caption)
                    }
                }
            }
            .navigationTitle("Settings")
            .onAppear {
                loadSettings()
            }
        }
    }
    
    private func addKeyword() {
        let keyword = newKeyword.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        guard !keyword.isEmpty, !telemetryKeywords.contains(keyword) else { return }
        
        telemetryKeywords.append(keyword)
        if !newKeywordUnit.isEmpty {
            keywordUnits[keyword] = newKeywordUnit.trimmingCharacters(in: .whitespacesAndNewlines)
        } else {
            // Use default unit from enum if available
            keywordUnits[keyword] = TelemetryKeyword(rawValue: keyword)?.unit ?? ""
        }
        
        newKeyword = ""
        newKeywordUnit = ""
    }
    
    private func addQuickKeyword(_ keyword: String, unit: String) {
        guard !telemetryKeywords.contains(keyword) else { return }
        
        telemetryKeywords.append(keyword)
        if !unit.isEmpty {
            keywordUnits[keyword] = unit
        }
    }
    
    private func deleteKeyword(_ keyword: String) {
        telemetryKeywords.removeAll { $0 == keyword }
        keywordUnits.removeValue(forKey: keyword)
    }
    
    private var isValidConfiguration: Bool {
        !host.isEmpty && !port.isEmpty && Int(port) != nil
    }
    
    private func loadSettings() {
        if let settings = brokerSettings.first {
            host = settings.host
            port = String(settings.port)
            username = settings.username
            password = settings.password
            clientId = settings.clientId
            keepAlive = String(settings.keepAlive)
        }
        
        if let config = telemetryConfigs.first {
            telemetryKeywords = config.keywords
            keywordUnits = config.keywordUnits
        }
    }
    
    private func saveBrokerSettings() {
        // Save broker settings only (no MQTT connection)
        let settings: BrokerSettings
        if let existing = brokerSettings.first {
            settings = existing
            settings.host = host
            settings.port = Int(port) ?? 1883
            settings.username = username
            settings.password = password
            if !clientId.isEmpty {
                settings.clientId = clientId
            }
            settings.keepAlive = Int(keepAlive) ?? 60
        } else {
            settings = BrokerSettings(
                host: host,
                port: Int(port) ?? 1883,
                username: username,
                password: password,
                clientId: clientId,
                keepAlive: Int(keepAlive) ?? 60
            )
            modelContext.insert(settings)
        }
        
        // Save to SwiftData
        try? modelContext.save()
    }
    
    private func saveKeywords() {
        // Save telemetry config only (no MQTT connection)
        let config: TelemetryConfig
        if let existing = telemetryConfigs.first {
            config = existing
            config.keywords = telemetryKeywords
            config.keywordUnits = keywordUnits
        } else {
            config = TelemetryConfig(deviceId: "", keywords: telemetryKeywords, keywordUnits: keywordUnits)
            modelContext.insert(config)
        }
        
        // Save to SwiftData
        try? modelContext.save()
    }
}

struct ConnectionStatusView: View {
    @EnvironmentObject var mqttViewModel: MqttViewModel
    
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
        }
    }
    
    private var statusColor: Color {
        switch mqttViewModel.connectionState {
        case .connected:
            return .green
        case .connecting:
            return .orange
        case .disconnected:
            return .gray
        case .error:
            return .red
        }
    }
    
    private var statusText: String {
        switch mqttViewModel.connectionState {
        case .connected:
            return "Connected"
        case .connecting:
            return "Connecting"
        case .disconnected:
            return "Disconnected"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}

struct PayloadLogRow: View {
    let entry: PayloadLogEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(entry.topic)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.blue)
                Spacer()
                Text(entry.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            
            Text(entry.payload)
                .font(.caption)
                .foregroundColor(.primary)
                .lineLimit(2)
        }
        .padding(8)
        .background(Color(.systemGray6))
        .cornerRadius(6)
    }
}

