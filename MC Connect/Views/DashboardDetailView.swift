//
//  DashboardDetailView.swift
//  MC Connect
//
//  Created by Martin Lanius on 24.10.25.
//

import SwiftUI
import SwiftData

struct DashboardDetailView: View {
    // non-private so the extension in DashboardHelper.swift can access them
    @Environment(\.modelContext) var modelContext
    @EnvironmentObject var mqtt: MqttViewModel

    @Bindable var dashboard: Dashboard
    init(dashboard: Dashboard) {
        self._dashboard = Bindable(wrappedValue: dashboard)
        print("[DashboardDetailView] init with dashboard.id=\(dashboard.id) dashboard.deviceId=\(dashboard.deviceId)")
    }

    @State var showingAddWidget = false

    // MQTT bookkeeping for this view (not private so extension can read/write)
    @State var localDevice: Device? = nil
    @State var connecting: Bool = false
    @State var lastConnectError: String? = nil

    private var columns: [GridItem] = [
        GridItem(.adaptive(minimum: 150), spacing: 12)
    ]

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(sortedWidgets) { w in
                    WidgetCard(
                        widget: w,
                        dashboard: dashboard,
                        onToggle: { newState in
                            // Ensure a deviceId (externalId) is configured for this dashboard
                            let deviceId = dashboard.deviceId
                            guard !deviceId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                                print("[DashboardDetailView] cannot toggle widget: dashboard.deviceId is missing")
                                return
                            }

                            // Use the central helper to publish the binary change (topic formatting + mqtt checks handled there)
                            publishBinaryChange(for: dashboard, widget: w, to: newState)

                            // Persist new state locally
                            w.value = newState ? 1 : 0
                            dashboard.updatedAt = Date()
                            try? modelContext.save()
                        }
                    )
                    .environmentObject(mqtt)
                }
            }
            .padding()
        }
        .navigationTitle(dashboard.name)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack {
                    connectionBadge
                    Button { showingAddWidget = true } label: { Image(systemName: "plus") }
                }
            }
        }
        .sheet(isPresented: $showingAddWidget) {
            WidgetInputView(dashboard: dashboard)
                .presentationDetents([.medium, .large])
        }
        .onAppear {
            print("[DashboardDetailView] onAppear - dashboard.id=\(dashboard.id) dashboard.deviceId=\(dashboard.deviceId)")
            Task { await startMqttForDashboard() }
        }
        .onDisappear {
            //stopMqttIfOwned()
        }
    }
}
