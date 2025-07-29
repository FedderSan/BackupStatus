// MARK: - Enhanced BackupManager with Dynamic Configuration
import Foundation
import SwiftData

@MainActor
class BackupManager: ObservableObject {
    @Published var currentStatus: BackupStatus = .success
    @Published var connectionStatus: ConnectionStatus = .unknown
    @Published var lastBackupTime: Date?
    @Published var lastConnectionTestTime: Date?
    @Published var isRunning = false
    
    private let dataActor: BackupDataActor
    private let logManager: LogManager
    
    // Dynamic configuration - loaded from settings
    private let rclonePath = "/usr/local/bin/rclone"
    private let sourcePath = "/Users/danielfeddersen/NextCloudMiniDaniel/Documents/"
    
    init(modelContainer: ModelContainer, logManager: LogManager) {
        self.dataActor = BackupDataActor(modelContainer: modelContainer)
        self.logManager = logManager
        Task {
            await loadLastBackupStatus()
        }
    }
    
    // MARK: - Dynamic Configuration Methods
    
    private func getBackupConfiguration() async -> (remoteName: String, remoteBasePath: String)? {
        guard let settings = await dataActor.getSettings() else {
            logManager.log("No settings found for backup configuration", level: .error)
            return nil
        }
        
        return (
            remoteName: settings.remoteName,
            remoteBasePath: settings.webdavPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        )
    }
    
    private func ensureRcloneConfig() async -> Bool {
        guard let settings = await dataActor.getSettings() else {
            logManager.log("No settings found for rclone configuration", level: .error)
            return false
        }
        
        let configPath = "/Users/danielfeddersen/.config/rclone/rclone.conf"
        let configContent = settings.generateRcloneConfig()
        
        do {
            // Check if config directory exists, create if not
            let configDir = URL(fileURLWithPath: configPath).deletingLastPathComponent()
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            
            // Write the configuration
            try configContent.write(toFile: configPath, atomically: true, encoding: .utf8)
            logManager.log("Updated rclone configuration at \(configPath)", level: .debug)
            return true
        } catch {
            logManager.log("Failed to write rclone config: \(error)", level: .error)
            return false
        }
    }
    
    func runBackup() async {
        guard await shouldRunBackup() else {
            currentStatus = .skipped
            logManager.updateBackupStatus(.skipped)
            logManager.log("Backup skipped - too soon since last successful backup", level: .info)
            return
        }
        
        // Ensure rclone configuration is up to date
        guard await ensureRcloneConfig() else {
            currentStatus = .failed
            logManager.updateBackupStatus(.failed)
            logManager.log("Failed to configure rclone", level: .error)
            return
        }
        
        logManager.log("Starting backup process...", level: .info)
        isRunning = true
        currentStatus = .running
        logManager.updateBackupStatus(.running)
        
        do {
            // Create session in database actor
            let session = await dataActor.createBackupSession()
            let sessionID = session.persistentModelID
            logManager.log("Created backup session with ID: \(sessionID)", level: .debug)
            
            // Perform backup work (can run on background threads)
            let result = await performBackupWork()
            
            if result.success {
                // Update session with success
                try await dataActor.updateSession(sessionID,
                                                success: true,
                                                error: nil,
                                                filesCount: result.filesCount,
                                                totalSize: result.totalSize)
                
                try await dataActor.updateLastSuccessfulBackup()
                currentStatus = .success
                logManager.updateBackupStatus(.success)
                logManager.log("Backup completed successfully - \(result.filesCount) files, \(ByteCountFormatter.string(fromByteCount: result.totalSize, countStyle: .file))", level: .info)
                
                // Perform cleanup
                await performCleanupWork()
                
            } else {
                // Update session with failure
                try await dataActor.updateSession(sessionID,
                                                success: false,
                                                error: result.error,
                                                filesCount: 0,
                                                totalSize: 0)
                
                if result.error?.contains("Connection") == true {
                    currentStatus = .connectionError
                    logManager.updateBackupStatus(.connectionError)
                    logManager.log("Backup failed due to connection error: \(result.error ?? "Unknown")", level: .error)
                } else {
                    currentStatus = .failed
                    logManager.updateBackupStatus(.failed)
                    logManager.log("Backup failed: \(result.error ?? "Unknown error")", level: .error)
                }
            }
            
        } catch {
            logManager.log("Database error during backup: \(error)", level: .error)
            currentStatus = .failed
            logManager.updateBackupStatus(.failed)
        }
        
        isRunning = false
        lastBackupTime = Date()
        logManager.log("Backup process finished with status: \(currentStatus.rawValue)", level: .info)
    }
    
    // MARK: - Enhanced Connection Test
    
    func runConnectionTest() async {
        logManager.log("🔄 Starting connection test...", level: .info)
        connectionStatus = .testing
        lastConnectionTestTime = Date()
        
        let isConnected = await testConnection()
        logManager.log("🔄 Connection test result: \(isConnected)", level: .info)
        connectionStatus = isConnected ? .connected : .failed
        logManager.log("🔄 Connection status set to: \(connectionStatus)", level: .debug)
    }
    
    func testConnection() async -> Bool {
        // Get settings from database
        guard let settings = await dataActor.getSettings() else {
            logManager.log("❌ No settings found in database", level: .error)
            return false
        }
        
        // Ensure rclone config is up to date
        guard await ensureRcloneConfig() else {
            logManager.log("❌ Failed to configure rclone", level: .error)
            return false
        }
        
        // Test 1: Network reachability using database settings
        if !(await testNetworkReachability(host: settings.serverHost)) {
            logManager.log("❌ Network unreachable to \(settings.serverHost)", level: .error)
            return false
        }
        
        // Test 2: WebDAV-specific connection test
        if settings.webdavEnabled {
            if !(await testWebDAVConnection(settings: settings)) {
                logManager.log("❌ WebDAV connection failed", level: .error)
                return false
            }
        }
        
        // Test 3: rclone connection
        if !(await testRcloneConnection(remoteName: settings.remoteName)) {
            logManager.log("❌ rclone connection failed", level: .error)
            return false
        }
        
        logManager.log("✅ All connection tests passed for \(settings.serverHost):\(settings.serverPort)", level: .info)
        return true
    }
    
    private func testWebDAVConnection(settings: BackupSettings) async -> Bool {
        logManager.log("Testing WebDAV connection to \(settings.fullWebDAVURL)", level: .debug)
        
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            
            var arguments = [
                "-s", "-f", "-X", "PROPFIND",
                "--user", "\(settings.webdavUsername):\(settings.webdavPassword)",
                "-H", "Content-Type: text/xml",
                "-H", "Depth: 0",
                "--max-time", "10"
            ]
            
            if !settings.webdavVerifySSL {
                arguments.append("-k")
            }
            
            arguments.append(settings.fullWebDAVURL)
            task.arguments = arguments
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                let success = task.terminationStatus == 0
                
                if !success {
                    let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    logManager.log("WebDAV connection failed: \(errorOutput)", level: .error)
                } else {
                    logManager.log("WebDAV connection successful", level: .debug)
                }
                
                continuation.resume(returning: success)
            } catch {
                logManager.log("WebDAV test error: \(error)", level: .error)
                continuation.resume(returning: false)
            }
        }
    }
    
    private func testNetworkReachability(host: String) async -> Bool {
        logManager.log("Testing network reachability to \(host)", level: .debug)
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/sbin/ping")
            task.arguments = ["-c", "1", "-W", "5000", host]
            
            do {
                try task.run()
                task.waitUntilExit()
                let success = task.terminationStatus == 0
                logManager.log("Ping to \(host): \(success ? "SUCCESS" : "FAILED")", level: success ? .debug : .warning)
                continuation.resume(returning: success)
            } catch {
                logManager.log("Failed to run ping to \(host): \(error)", level: .error)
                continuation.resume(returning: false)
            }
        }
    }
    
    private func testRcloneConnection(remoteName: String) async -> Bool {
        logManager.log("Testing rclone connection to \(remoteName):", level: .debug)
        return await withCheckedContinuation { continuation in
            let task = Process()
            
            task.executableURL = URL(fileURLWithPath: rclonePath)
            task.arguments = ["lsd", "\(remoteName):", "--timeout", "30s"]
            
            var environment = ProcessInfo.processInfo.environment
            environment["RCLONE_CONFIG"] = "/Users/danielfeddersen/.config/rclone/rclone.conf"
            task.environment = environment
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                let success = task.terminationStatus == 0
                
                if !success {
                    let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    logManager.log("rclone connection failed: \(errorOutput)", level: .error)
                } else {
                    logManager.log("rclone connection successful", level: .debug)
                }
                
                continuation.resume(returning: success)
            } catch {
                logManager.log("rclone test error: \(error)", level: .error)
                continuation.resume(returning: false)
            }
        }
    }
    
    // MARK: - Enhanced Backup Work with Dynamic Configuration
    
    private func performBackupWork() async -> (success: Bool, error: String?, filesCount: Int, totalSize: Int64) {
        guard let config = await getBackupConfiguration() else {
            return (false, "Failed to load backup configuration", 0, 0)
        }
        
        // Test connection and update status
        logManager.log("🔄 Testing connection during backup...", level: .debug)
        connectionStatus = .testing
        lastConnectionTestTime = Date()
        
        let isConnected = await testConnection()
        logManager.log("🔄 Backup connection test result: \(isConnected)", level: .debug)
        connectionStatus = isConnected ? .connected : .failed
        logManager.log("🔄 Backup connection status set to: \(connectionStatus)", level: .debug)
        
        if !isConnected {
            return (false, "Connection failed", 0, 0)
        }
        
        // Do backup with dynamic configuration
        return await performNativeBackup(remoteName: config.remoteName, remoteBasePath: config.remoteBasePath)
    }
    
    private func performNativeBackup(remoteName: String, remoteBasePath: String) async -> (success: Bool, error: String?, filesCount: Int, totalSize: Int64) {
        let dateDaily = DateFormatter.dailyFormat.string(from: Date())
        let dateVersion = DateFormatter.versionFormat.string(from: Date())
        
        // Step 1: Daily sync
        logManager.log("Starting daily sync to \(dateDaily)", level: .info)
        let dailySyncResult = await runRcloneCommand([
            "sync",
            sourcePath,
            "\(remoteName):\(remoteBasePath)/daily/\(dateDaily)",
            "--progress",
            "--transfers", "4",
            "--checkers", "8",
            "--timeout", "300s",
            "--retries", "3"
        ])
        
        if !dailySyncResult.success {
            logManager.log("Daily sync failed: \(dailySyncResult.error ?? "Unknown error")", level: .error)
            return (false, "Daily sync failed: \(dailySyncResult.error ?? "Unknown error")", 0, 0)
        }
        logManager.log("Daily sync completed successfully", level: .info)
        
        // Step 2: Current copy with versioning
        logManager.log("Starting version backup to \(dateVersion)", level: .info)
        let versionResult = await runRcloneCommand([
            "copy",
            sourcePath,
            "\(remoteName):\(remoteBasePath)/current",
            "--update",
            "--backup-dir", "\(remoteName):\(remoteBasePath)/versions/\(dateVersion)",
            "--progress",
            "--transfers", "4",
            "--timeout", "300s",
            "--retries", "3"
        ])
        
        if !versionResult.success {
            logManager.log("Version backup failed: \(versionResult.error ?? "Unknown error")", level: .error)
            return (false, "Version backup failed: \(versionResult.error ?? "Unknown error")", 0, 0)
        }
        logManager.log("Version backup completed successfully", level: .info)
        
        // Get file count and size
        let stats = await getBackupStats(remoteName: remoteName, remoteBasePath: remoteBasePath, dateFolder: dateDaily)
        logManager.log("Backup statistics: \(stats.fileCount) files, \(ByteCountFormatter.string(fromByteCount: stats.totalSize, countStyle: .file))", level: .info)
        
        return (true, nil, stats.fileCount, stats.totalSize)
    }
    
    private func runRcloneCommand(_ arguments: [String]) async -> (success: Bool, error: String?) {
        let command = "\(rclonePath) \(arguments.joined(separator: " "))"
        logManager.log("Executing: \(command)", level: .debug)
        
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: rclonePath)
            task.arguments = arguments
            
            var environment = ProcessInfo.processInfo.environment
            environment["RCLONE_CONFIG"] = "/Users/danielfeddersen/.config/rclone/rclone.conf"
            task.environment = environment
            
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            task.standardOutput = outputPipe
            task.standardError = errorPipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                if task.terminationStatus == 0 {
                    logManager.log("Command completed successfully: \(arguments[0])", level: .debug)
                    continuation.resume(returning: (true, nil))
                } else {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    logManager.log("Command failed (\(task.terminationStatus)): \(errorOutput)", level: .error)
                    continuation.resume(returning: (false, errorOutput))
                }
            } catch {
                logManager.log("Failed to execute command: \(error.localizedDescription)", level: .error)
                continuation.resume(returning: (false, error.localizedDescription))
            }
        }
    }
    
    private func getBackupStats(remoteName: String, remoteBasePath: String, dateFolder: String) async -> (fileCount: Int, totalSize: Int64) {
        logManager.log("Getting backup statistics for \(dateFolder)", level: .debug)
        let result = await runRcloneCommand([
            "size",
            "\(remoteName):\(remoteBasePath)/daily/\(dateFolder)",
            "--json"
        ])
        
        guard result.success else {
            logManager.log("Failed to get backup statistics", level: .warning)
            return (0, 0)
        }
        
        // TODO: Parse actual JSON response from rclone size command
        // For now, return placeholder values
        return (150, 1024000)
    }
    
    private func performCleanupWork() async {
        guard let config = await getBackupConfiguration() else {
            logManager.log("Failed to load configuration for cleanup", level: .error)
            return
        }
        
        logManager.log("Starting cleanup process", level: .info)
        
        logManager.log("Cleaning old daily backups (older than 14 days)", level: .debug)
        let dailyCleanup = await runRcloneCommand([
            "delete",
            "\(config.remoteName):\(config.remoteBasePath)/daily/",
            "--min-age", "14d"
        ])
        
        if dailyCleanup.success {
            logManager.log("Daily cleanup completed", level: .debug)
        } else {
            logManager.log("Daily cleanup failed: \(dailyCleanup.error ?? "Unknown")", level: .warning)
        }
        
        logManager.log("Cleaning old version backups (older than 30 days)", level: .debug)
        let versionCleanup = await runRcloneCommand([
            "delete",
            "\(config.remoteName):\(config.remoteBasePath)/versions/",
            "--min-age", "30d"
        ])
        
        if versionCleanup.success {
            logManager.log("Version cleanup completed", level: .debug)
        } else {
            logManager.log("Version cleanup failed: \(versionCleanup.error ?? "Unknown")", level: .warning)
        }
        
        logManager.log("Cleanup process finished", level: .info)
    }
    
    // MARK: - Database Helper Methods (Using Actor)
    
    private func shouldRunBackup() async -> Bool {
        guard let settings = await dataActor.getSettings() else {
            logManager.log("No settings found, allowing backup to run", level: .debug)
            return true
        }
        
        if isRunning {
            logManager.log("Backup already running, skipping", level: .debug)
            return false
        }
        
        if let lastSuccess = settings.lastSuccessfulBackup {
            let hoursSinceLastBackup = Date().timeIntervalSince(lastSuccess) / 3600
            if hoursSinceLastBackup < Double(settings.backupIntervalHours) {
                logManager.log("Backup skipped - last successful backup was \(Int(hoursSinceLastBackup)) hours ago", level: .info)
                return false
            }
        }
        
        return true
    }
    
    func getRecentSessions(limit: Int = 10) async -> [BackupSession] {
        return await dataActor.getRecentSessions(limit: limit)
    }
    
    func loadLastBackupStatus() async {
        let recent = await dataActor.getRecentSessions(limit: 1)
        if let last = recent.first {
            currentStatus = last.status
            logManager.updateBackupStatus(last.status)
            lastBackupTime = last.endTime ?? last.startTime
            logManager.log("Loaded last backup status: \(last.status.rawValue)", level: .debug)
        }
    }
    
    func cleanOldSessions() async {
        await dataActor.cleanOldSessions()
        logManager.log("Cleaned old backup sessions", level: .debug)
    }
    
    // MARK: - Settings Access Methods
    
    func getSettings() async -> BackupSettings? {
        return await dataActor.getSettings()
    }
    
    func getOrCreateSettings() async -> BackupSettings {
        return await dataActor.getOrCreateSettings()
    }
    
    // MARK: - WebDAV Specific Methods
    
    func testWebDAVCredentials() async -> Bool {
        guard let settings = await dataActor.getSettings() else {
            return false
        }
        
        return await testWebDAVConnection(settings: settings)
    }
    
    func validateWebDAVPath() async -> Bool {
        guard let settings = await dataActor.getSettings() else {
            return false
        }
        
        logManager.log("Validating WebDAV path: \(settings.webdavPath)", level: .debug)
        
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            
            var arguments = [
                "-s", "-f", "-X", "PROPFIND",
                "--user", "\(settings.webdavUsername):\(settings.webdavPassword)",
                "-H", "Content-Type: text/xml",
                "-H", "Depth: 1",
                "--max-time", "10"
            ]
            
            if !settings.webdavVerifySSL {
                arguments.append("-k")
            }
            
            let fullPath = settings.fullWebDAVURL + settings.webdavPath
            arguments.append(fullPath)
            task.arguments = arguments
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                let success = task.terminationStatus == 0
                
                if success {
                    logManager.log("WebDAV path validation successful", level: .debug)
                } else {
                    let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    logManager.log("WebDAV path validation failed: \(errorOutput)", level: .error)
                }
                
                continuation.resume(returning: success)
            } catch {
                logManager.log("WebDAV path validation error: \(error)", level: .error)
                continuation.resume(returning: false)
            }
        }
    }
}


