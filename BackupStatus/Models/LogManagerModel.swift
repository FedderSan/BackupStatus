//
//  LogManager.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 26/07/2025.
//

import Foundation
import SwiftUI

// MARK: - Log Entry Model
struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let level: LogLevel
    let message: String
    
    enum LogLevel: String, CaseIterable {
        case debug = "DEBUG"
        case info = "INFO"
        case warning = "WARNING"
        case error = "ERROR"
        
        var color: Color {
            switch self {
            case .debug: return .gray
            case .info: return .blue
            case .warning: return .orange
            case .error: return .red
            }
        }
        
        var icon: String {
            switch self {
            case .debug: return "text.alignleft"
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error: return "xmark.circle"
            }
        }
    }
}

// MARK: - Log Manager
@MainActor
class LogManager: ObservableObject {
    @Published var logEntries: [LogEntry] = []
    @Published var currentBackupStatus: BackupStatus = .success
    private let maxLogEntries = 1000
    
    func log(_ message: String, level: LogEntry.LogLevel = .info) {
        let entry = LogEntry(timestamp: Date(), level: level, message: message)
        logEntries.append(entry)
        
        // Keep only the most recent entries
        if logEntries.count > maxLogEntries {
            logEntries.removeFirst(logEntries.count - maxLogEntries)
        }
        
        // Also print to console for Xcode debugging
        print("[\(level.rawValue)] \(message)")
    }
    
    func clearLogs() {
        logEntries.removeAll()
    }
    
    func updateBackupStatus(_ status: BackupStatus) {
        currentBackupStatus = status
    }
    
    func exportLogs() -> String {
        return logEntries.map { entry in
            "[\(entry.timestamp.formatted())] [\(entry.level.rawValue)] \(entry.message)"
        }.joined(separator: "\n")
    }
}
