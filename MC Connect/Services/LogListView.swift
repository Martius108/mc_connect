//
//  LogListView.swift
//  MC Connect
//
//  Created by Martin Lanius on 23.10.25.
//

import SwiftUI

struct LogListView: View {
    let messages: [MqttMessage]
    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(messages) { m in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.topic)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(m.payload)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.06))
                    .cornerRadius(6)
                }
            }
            .padding(.vertical, 4)
        }
    }
}
