//
//  BackupManager+StartupStats.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 21/10/2025.
//
import Foundation

extension BackupManager {
    // MARK: - Startup Diagnostics
    
    func runStartupDiagnostics() async {
        logManager.log("🔍 Running startup diagnostics...", level: .info)
        
        // Database diagnostics
        logManager.log("📊 Database diagnostics:", level: .info)
        let sessionCount = await dataActor.getRecentSessions(limit: 100).count
        let settings = await dataActor.getSettings()
        
        logManager.log("  - Total sessions in database: \(sessionCount)", level: .info)
        logManager.log("  - Settings configured: \(settings != nil ? "Yes" : "No")", level: .info)
        
        if let settings = settings {
            let validation = settings.validateConfiguration()
            logManager.log("  - Configuration valid: \(validation.isValid)", level: .info)
            logManager.log("  - Log retention: \(settings.logRetentionPeriod.displayName)", level: .info)
            if !validation.isValid {
                logManager.log("  - Configuration errors: \(validation.errors.joined(separator: ", "))", level: .warning)
            }
        }
        
        // Log statistics
        let logStats = await logManager.getLogStatistics()
        logManager.log("📝 Log diagnostics:", level: .info)
        logManager.log("  - Total persisted logs: \(logStats.total)", level: .info)
        if let oldest = logStats.oldestDate, let newest = logStats.newestDate {
            logManager.log("  - Date range: \(oldest.formatted(date: .abbreviated, time: .shortened)) to \(newest.formatted(date: .abbreviated, time: .shortened))", level: .info)
        }
        for (level, count) in logStats.byLevel {
            logManager.log("  - \(level.displayName): \(count)", level: .info)
        }
        
        // System diagnostics
        logManager.log("🖥️ System diagnostics:", level: .info)
        logManager.log("  - App bundle: \(Bundle.main.bundlePath)", level: .info)
        logManager.log("  - Home directory: \(FileManager.default.homeDirectoryForCurrentUser.path)", level: .info)
        logManager.log("  - rclone path: \(rclonePath) (exists: \(FileManager.default.fileExists(atPath: rclonePath)))", level: .info)
        logManager.log("  - Config path: \(configPath)", level: .info)
        
        // Application Support directory diagnostics
        let appSupportURL = URL.applicationSupportDirectory.appendingPathComponent("BackupStatus", isDirectory: true)
        let databaseURL = appSupportURL.appendingPathComponent("BackupStatus.store")
        
        logManager.log("📁 File system diagnostics:", level: .info)
        logManager.log("  - App Support exists: \(FileManager.default.fileExists(atPath: appSupportURL.path))", level: .info)
        logManager.log("  - Database exists: \(FileManager.default.fileExists(atPath: databaseURL.path))", level: .info)
        
        if FileManager.default.fileExists(atPath: databaseURL.path) {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: databaseURL.path)
                if let size = attributes[.size] as? Int64 {
                    logManager.log("  - Database size: \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))", level: .info)
                }
                if let modDate = attributes[.modificationDate] as? Date {
                    logManager.log("  - Database last modified: \(modDate.formatted(date: .abbreviated, time: .shortened))", level: .info)
                }
            } catch {
                logManager.log("  - Error reading database attributes: \(error)", level: .error)
            }
        }
        
        logManager.log("✅ Startup diagnostics completed", level: .info)
    }
}
