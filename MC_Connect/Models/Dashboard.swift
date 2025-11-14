//
//  Dashboard.swift
//  MC_Connect
//
//  Created by Martin Lanius on 09.11.25.
//

import Foundation
import SwiftData

@Model
final class Dashboard {
    var id: UUID
    var name: String
    var deviceIds: [String] // Array of device IDs
    var widgets: [Widget]?
    
    init(id: UUID = UUID(), name: String, deviceIds: [String] = []) {
        self.id = id
        self.name = name
        self.deviceIds = deviceIds
        self.widgets = []
    }
}

