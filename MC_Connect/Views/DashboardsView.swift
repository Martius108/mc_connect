//
//  DashboardsView.swift
//  MC_Connect
//
//  Created by Martin Lanius on 09.11.25.
//

import SwiftUI
import SwiftData

struct DashboardsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Dashboard.name) private var dashboards: [Dashboard]
    @Query private var devices: [Device]
    @State private var showingAddDashboard = false
    @State private var showingEditDashboard: Dashboard?
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(dashboards) { dashboard in
                    NavigationLink {
                        DashboardDetailView(dashboard: dashboard)
                    } label: {
                        DashboardRow(dashboard: dashboard, devices: devices)
                    }
                    .contextMenu {
                        Button {
                            showingEditDashboard = dashboard
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        
                        Button(role: .destructive) {
                            deleteDashboard(dashboard)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onDelete(perform: deleteDashboards)
            }
            .navigationTitle("Dashboards")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddDashboard = true
                    } label: {
                        Label("Add Dashboard", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddDashboard) {
                AddDashboardView()
            }
            .sheet(item: $showingEditDashboard) { dashboard in
                EditDashboardView(dashboard: dashboard)
            }
        }
    }
    
    private func deleteDashboards(offsets: IndexSet) {
        withAnimation {
            for index in offsets {
                modelContext.delete(dashboards[index])
            }
        }
    }
    
    private func deleteDashboard(_ dashboard: Dashboard) {
        withAnimation {
            modelContext.delete(dashboard)
        }
    }
}

struct DashboardRow: View {
    let dashboard: Dashboard
    let devices: [Device]
    
    var dashboardDevices: [Device] {
        devices.filter { dashboard.deviceIds.contains($0.id) }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(dashboard.name)
                .font(.headline)
            
            if !dashboardDevices.isEmpty {
                HStack {
                    ForEach(dashboardDevices.prefix(3)) { device in
                        HStack(spacing: 4) {
                            Circle()
                                .fill(device.isOnline ? Color.green : Color.gray)
                                .frame(width: 8, height: 8)
                            Text(device.name)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    if dashboardDevices.count > 3 {
                        Text("+\(dashboardDevices.count - 3) more")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            } else {
                Text("No devices")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

struct AddDashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var devices: [Device]
    
    @State private var name: String = ""
    @State private var selectedDeviceIds: Set<String> = []
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Dashboard Information") {
                    TextField("Dashboard Name", text: $name)
                        .onSubmit { hideKeyboard() }
                }
                
                Section("Devices") {
                    if devices.isEmpty {
                        Text("No devices available. Add devices first.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(devices) { device in
                            Toggle(device.name, isOn: Binding(
                                get: { selectedDeviceIds.contains(device.id) },
                                set: { isSelected in
                                    if isSelected {
                                        selectedDeviceIds.insert(device.id)
                                    } else {
                                        selectedDeviceIds.remove(device.id)
                                    }
                                }
                            ))
                        }
                    }
                }
            }
            .navigationTitle("Add Dashboard")
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
                        saveDashboard()
                    }
                    .disabled(name.isEmpty)
                }
            }
        }
    }
    
    private func saveDashboard() {
        let dashboard = Dashboard(
            name: name,
            deviceIds: Array(selectedDeviceIds)
        )
        modelContext.insert(dashboard)
        dismiss()
    }
}

struct EditDashboardView: View {
    let dashboard: Dashboard
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query private var devices: [Device]
    
    @State private var name: String = ""
    @State private var selectedDeviceIds: Set<String> = []
    
    var body: some View {
        NavigationStack {
            Form {
                Section("Dashboard Information") {
                    TextField("Dashboard Name", text: $name)
                        .onSubmit { hideKeyboard() }
                }
                
                Section("Devices") {
                    if devices.isEmpty {
                        Text("No devices available. Add devices first.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(devices) { device in
                            Toggle(device.name, isOn: Binding(
                                get: { selectedDeviceIds.contains(device.id) },
                                set: { isSelected in
                                    if isSelected {
                                        selectedDeviceIds.insert(device.id)
                                    } else {
                                        selectedDeviceIds.remove(device.id)
                                    }
                                }
                            ))
                        }
                    }
                }
            }
            .navigationTitle("Edit Dashboard")
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
                        saveDashboard()
                    }
                    .disabled(name.isEmpty)
                }
            }
            .onAppear {
                name = dashboard.name
                selectedDeviceIds = Set(dashboard.deviceIds)
            }
        }
    }
    
    private func saveDashboard() {
        dashboard.name = name
        dashboard.deviceIds = Array(selectedDeviceIds)
        dismiss()
    }
}
