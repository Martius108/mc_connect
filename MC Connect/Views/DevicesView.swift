//
//  DevicesView.swift
//  MC Connect
//

import SwiftUI
import SwiftData

struct DevicesView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var devices: [Device]

    @State private var showingAddSheet = false

    var body: some View {
        NavigationView {
            List {
                ForEach(devices) { device in
                    NavigationLink(destination: DeviceDetailView(device: device)) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(device.name)
                                    .font(.headline)
                                Text(device.type)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            ConnectionStatusDot(connected: device.isActive)
                        }
                    }
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
                        modelContext.insert(device)
                        do {
                            try modelContext.save()
                        } catch {
                            print("Fehler beim Speichern des Geräts:", error)
                        }
                    },
                    onCreate: { device in
                        // z. B. für spezielle Logik bei Erstellung
                        modelContext.insert(device)
                        do {
                            try modelContext.save()
                        } catch {
                            print("Fehler beim Erstellen des Geräts:", error)
                        }
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
}
