//
//  ConnectionsStatusDot.swift
//  MC Connect
//
//  Created by Martin Lanius on 23.10.25.
//

import SwiftUI

struct ConnectionStatusDot: View {
    let connected: Bool
    var body: some View {
        Circle()
            .fill(connected ? Color.green : Color.red)
            .frame(width: 10, height: 10)
    }
}
