import SwiftUI
import Foundation
import SwiftData
import UniformTypeIdentifiers

// MARK: - Updated LogManager with Persistence and Configurable Retention
@MainActor
class LogManager: ObservableObject {
    @Published var logs: [LogEntry] = []
    @Published var currentBackupStatus: BackupStatus = .success
    
    private let maxInMemoryEntries = 1000
    private let maxDatabaseEntries = 5000
    private var logUpdateTask: Task<Void, Never>?
    private let modelContainer: ModelContainer
    
    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        loadPersistedLogs()
    }
    
    func log(_ message: String, level: LogLevel = .info) {
        // Cancel previous update to prevent rapid updates
        logUpdateTask?.cancel()
        
        logUpdateTask = Task { @MainActor in
            let entry = LogEntry(message: message, level: level, timestamp: Date())
            
            // Add to in-memory logs array
            logs.append(entry)
            
            // Keep only recent entries in memory
            if logs.count > maxInMemoryEntries {
                logs.removeFirst(logs.count - maxInMemoryEntries)
            }
            
            // Persist to database
            await persistLog(entry)
            
            // Print to console as well
            print("[\(entry.timestamp)] [\(level.displayName)] \(message)")
        }
    }
    
    private func persistLog(_ entry: LogEntry) async {
        let context = ModelContext(modelContainer)
        
        // Create persistent entry
        let persistentEntry = PersistentLogEntry(
            message: entry.message,
            level: entry.level,
            timestamp: entry.timestamp
        )
        
        context.insert(persistentEntry)
        
        do {
            try context.save()
            
            // Clean old logs periodically (every 50 new logs)
            if logs.count % 50 == 0 {
                await cleanOldPersistedLogs(context: context)
            }
        } catch {
            print("Failed to persist log: \(error)")
        }
    }
    
    private func cleanOldPersistedLogs(context: ModelContext) async {
        // Get current retention setting
        let settingsContext = ModelContext(modelContainer)
        let settingsDescriptor = FetchDescriptor<BackupSettings>()
        
        guard let settings = try? settingsContext.fetch(settingsDescriptor).first else {
            // Default to 30 days if no settings
            await cleanLogsOlderThan(LogRetentionPeriod.days30.cutoffDate, context: context)
            return
        }
        
        let cutoffDate = settings.logRetentionPeriod.cutoffDate
        await cleanLogsOlderThan(cutoffDate, context: context)
    }
    
    private func cleanLogsOlderThan(_ cutoffDate: Date, context: ModelContext) async {
        let descriptor = FetchDescriptor<PersistentLogEntry>(
            predicate: #Predicate<PersistentLogEntry> { log in
                log.timestamp < cutoffDate
            }
        )
        
        do {
            let oldLogs = try context.fetch(descriptor)
            if !oldLogs.isEmpty {
                for log in oldLogs {
                    context.delete(log)
                }
                try context.save()
                print("Cleaned \(oldLogs.count) old log entries older than \(cutoffDate)")
            }
            
            // Also ensure we don't exceed max database entries
            let allLogsDescriptor = FetchDescriptor<PersistentLogEntry>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            
            let allLogs = try context.fetch(allLogsDescriptor)
            if allLogs.count > maxDatabaseEntries {
                let logsToDelete = Array(allLogs.dropFirst(maxDatabaseEntries))
                for log in logsToDelete {
                    context.delete(log)
                }
                try context.save()
                print("Cleaned \(logsToDelete.count) excess log entries (keeping \(maxDatabaseEntries) most recent)")
            }
        } catch {
            print("Failed to clean old logs: \(error)")
        }
    }
    
    private func loadPersistedLogs() {
        Task {
            let context = ModelContext(modelContainer)
            var descriptor = FetchDescriptor<PersistentLogEntry>(
                sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
            )
            descriptor.fetchLimit = maxInMemoryEntries
            
            do {
                let persistedLogs = try context.fetch(descriptor)
                
                await MainActor.run {
                    // Convert to LogEntry and reverse to show newest first in memory
                    self.logs = persistedLogs.reversed().map { persistent in
                        LogEntry(
                            message: persistent.message,
                            level: persistent.level,
                            timestamp: persistent.timestamp
                        )
                    }
                    
                    print("Loaded \(self.logs.count) persisted logs")
                    
                    // Log a startup message to confirm persistence is working
                    if !self.logs.isEmpty {
                        self.log("📱 Application restarted - loaded \(self.logs.count) existing log entries", level: .info)
                    } else {
                        self.log("📱 Application started - no previous logs found", level: .info)
                    }
                }
            } catch {
                print("Failed to load persisted logs: \(error)")
                await MainActor.run {
                    self.log("⚠️ Failed to load persisted logs: \(error)", level: .warning)
                }
            }
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
            
            // Also clear persisted logs
            let context = ModelContext(modelContainer)
            let descriptor = FetchDescriptor<PersistentLogEntry>()
            
            do {
                let allLogs = try context.fetch(descriptor)
                let count = allLogs.count
                for log in allLogs {
                    context.delete(log)
                }
                try context.save()
                
                await MainActor.run {
                    self.log("🗑️ Cleared \(count) persisted log entries", level: .info)
                }
            } catch {
                print("Failed to clear persisted logs: \(error)")
                await MainActor.run {
                    self.log("❌ Failed to clear persisted logs: \(error)", level: .error)
                }
            }
        }
    }
    
    func getLogStatistics() async -> (total: Int, byLevel: [LogLevel: Int], oldestDate: Date?, newestDate: Date?) {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PersistentLogEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        
        do {
            let allLogs = try context.fetch(descriptor)
            let total = allLogs.count
            
            var byLevel: [LogLevel: Int] = [:]
            for log in allLogs {
                byLevel[log.level, default: 0] += 1
            }
            
            let oldestDate = allLogs.last?.timestamp
            let newestDate = allLogs.first?.timestamp
            
            return (total, byLevel, oldestDate, newestDate)
        } catch {
            return (0, [:], nil, nil)
        }
    }
    
    func forceCleanOldLogs() async {
        log("🧹 Manually cleaning old logs...", level: .info)
        let context = ModelContext(modelContainer)
        await cleanOldPersistedLogs(context: context)
        
        // Reload logs after cleaning
        loadPersistedLogs()
    }
    
    func exportLogs() -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        
        return logs.map { entry in
            "[\(formatter.string(from: entry.timestamp))] [\(entry.level.displayName)] \(entry.message)"
        }.joined(separator: "\n")
    }
    
    func exportAllLogsFromDatabase() async -> String {
        let context = ModelContext(modelContainer)
        let descriptor = FetchDescriptor<PersistentLogEntry>(
            sortBy: [SortDescriptor(\.timestamp, order: .forward)]
        )
        
        do {
            let allLogs = try context.fetch(descriptor)
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .medium
            
            return allLogs.map { entry in
                "[\(formatter.string(from: entry.timestamp))] [\(entry.level.displayName)] \(entry.message)"
            }.joined(separator: "\n")
        } catch {
            return "Error exporting logs: \(error)"
        }
    }
}

// MARK: - Keep the existing LogEntry struct for in-memory use
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
