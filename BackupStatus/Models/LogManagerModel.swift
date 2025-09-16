import SwiftUI
import Foundation
import UniformTypeIdentifiers

@MainActor
class LogManager: ObservableObject {
    @Published var logs: [LogEntry] = []
    @Published var currentBackupStatus: BackupStatus = .success
    
    private let maxLogEntries = 1000
    private var logUpdateTask: Task<Void, Never>?
    
    func log(_ message: String, level: LogLevel = .info) {
        // Cancel previous update to prevent rapid updates
        logUpdateTask?.cancel()
        
        logUpdateTask = Task { @MainActor in
            let entry = LogEntry(message: message, level: level, timestamp: Date())
            
            // Add to logs array
            logs.append(entry)
            
            // Keep only recent entries
            if logs.count > maxLogEntries {
                logs.removeFirst(logs.count - maxLogEntries)
            }
            
            // Print to console as well
            print("[\(entry.timestamp)] [\(level.displayName)] \(message)")
        }
    }
    
    func updateBackupStatus(_ status: BackupStatus) {
        Task { @MainActor in
            self.currentBackupStatus = status
        }
    }
    
    func clearLogs() {
        Task { @MainActor in
            logs.removeAll()
        }
    }
    
    func exportLogs() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        
        return logs.map { entry in
            "[\(formatter.string(from: entry.timestamp))] [\(entry.level.displayName)] \(entry.message)"
        }.joined(separator: "\n")
    }
}

struct LogEntry: Identifiable, Hashable {
    let id = UUID()
    let message: String
    let level: LogLevel
    let timestamp: Date
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: LogEntry, rhs: LogEntry) -> Bool {
        lhs.id == rhs.id
    }
}

enum LogLevel: String, CaseIterable, Hashable {
    case debug = "debug"
    case info = "info"
    case warning = "warning"
    case error = "error"
    
    var displayName: String {
        switch self {
        case .debug: return "DEBUG"
        case .info: return "INFO"
        case .warning: return "WARN"
        case .error: return "ERROR"
        }
    }
    
    var color: Color {
        switch self {
        case .debug: return .gray
        case .info: return .blue
        case .warning: return .orange
        case .error: return .red
        }
    }
    
    var systemImage: String {
        switch self {
        case .debug: return "ladybug"
        case .info: return "info.circle"
        case .warning: return "exclamationmark.triangle"
        case .error: return "xmark.circle"
        }
    }
}
