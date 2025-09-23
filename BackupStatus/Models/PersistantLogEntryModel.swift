//
//  PersistantLogEntryModel.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 18/09/2025.
//

import SwiftUI
import Foundation
import SwiftData
import UniformTypeIdentifiers

// MARK: - Persistent Log Entry Model
@Model
class PersistentLogEntry {
    var id: UUID
    var message: String
    var levelRawValue: String
    var timestamp: Date
    
    init(message: String, level: LogLevel, timestamp: Date = Date()) {
        self.id = UUID()
        self.message = message
        self.levelRawValue = level.rawValue
        self.timestamp = timestamp
    }
    
    var level: LogLevel {
        return LogLevel(rawValue: levelRawValue) ?? .info
    }
}
