//
//  DashboardView.swift
//  MC Connect
//
//  Created by Martin Lanius on 23.10.25.
//

import SwiftUI
import SwiftData

struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Dashboard.createdAt, order: .reverse) private var dashboards: [Dashboard]

    @State private var showingAdd = false

    var body: some View {
        NavigationView {
            Group {
                if dashboards.isEmpty {
                    VStack(spacing: 12) {
                        Text("Noch kein Dashboard")
                            .font(.title3)
                            .foregroundColor(.secondary)
                        Button {
                            showingAdd = true
                        } label: {
                            Label("Neues Dashboard anlegen", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(dashboards) { db in
                            NavigationLink(destination: DashboardDetailView(dashboard: db)) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(db.name).font(.headline)
                                    if let info = db.info, !info.isEmpty {
                                        Text(info).font(.subheadline).foregroundColor(.secondary)
                                    }
                                }
                            }
                        }
                        .onDelete(perform: deleteDashboards)
                    }
                }
            }
            .navigationTitle("Dashboard")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { showingAdd = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showingAdd) {
                DashboardInputView { name, info, device in
                    let db = Dashboard(name: name, info: info)
                    modelContext.insert(db)
                    try? modelContext.save()
                }
                .presentationDetents([.medium, .large])
            }
        }
    }

    private func deleteDashboards(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(dashboards[index])
        }
        try? modelContext.save()
    }
}
