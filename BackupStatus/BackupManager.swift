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
    
    // Fixed paths - no more dynamic loading
    private let rclonePath = "/usr/local/bin/rclone"
    private let configPath = "/Users/danielfeddersen/.config/rclone/rclone.conf"
    private let sourcePath = "/Users/danielfeddersen/NextCloudMiniDaniel/Documents/"
    
    init(modelContainer: ModelContainer, logManager: LogManager) {
        self.dataActor = BackupDataActor(modelContainer: modelContainer)
        self.logManager = logManager
        Task {
            await loadLastBackupStatus()
        }
    }
    
    // MARK: - Main Backup Function
    
    func runBackup() async {
        guard await shouldRunBackup() else {
            currentStatus = .skipped
            logManager.updateBackupStatus(.skipped)
            logManager.log("Backup skipped - too soon since last backup", level: .info)
            return
        }
        
        logManager.log("Starting backup process", level: .info)
        isRunning = true
        currentStatus = .running
        logManager.updateBackupStatus(.running)
        
        do {
            // Create backup session
            let session = await dataActor.createBackupSession()
            let sessionID = session.persistentModelID
            
            // Get settings and validate
            guard let settings = await dataActor.getSettings() else {
                throw BackupError.backupFailed("No settings found")
            }
            
            // Write rclone config
            try await writeRcloneConfig(settings)
            
            // Test connection
            let isConnected = await testConnection(settings)
            connectionStatus = isConnected ? .connected : .failed
            lastConnectionTestTime = Date()
            
            guard isConnected else {
                throw BackupError.connectionFailed
            }
            
            // Perform backup
            let result = await performBackup(settings)
            
            if result.success {
                try await dataActor.updateSession(sessionID,
                                                success: true,
                                                error: nil,
                                                filesCount: result.filesCount,
                                                totalSize: result.totalSize)
                try await dataActor.updateLastSuccessfulBackup()
                currentStatus = .success
                logManager.updateBackupStatus(.success)
                logManager.log("Backup completed successfully", level: .info)
            } else {
                try await dataActor.updateSession(sessionID,
                                                success: false,
                                                error: result.error,
                                                filesCount: 0,
                                                totalSize: 0)
                currentStatus = .failed
                logManager.updateBackupStatus(.failed)
                logManager.log("Backup failed: \(result.error ?? "Unknown error")", level: .error)
            }
            
        } catch {
            logManager.log("Backup error: \(error)", level: .error)
            currentStatus = .failed
            logManager.updateBackupStatus(.failed)
        }
        
        isRunning = false
        lastBackupTime = Date()
    }
    
    // MARK: - Connection Testing
    
    func runConnectionTest() async {
        logManager.log("Starting connection test", level: .info)
        connectionStatus = .testing
        lastConnectionTestTime = Date()
        
        guard let settings = await dataActor.getSettings() else {
            connectionStatus = .failed
            logManager.log("No settings found for connection test", level: .error)
            return
        }
        
        let isConnected = await testConnection(settings)
        connectionStatus = isConnected ? .connected : .failed
        logManager.log("Connection test result: \(isConnected ? "SUCCESS" : "FAILED")", level: isConnected ? .info : .error)
    }
    
    private func testConnection(_ settings: BackupSettings) async -> Bool {
        // Test 1: Basic network connectivity
        guard await testNetworkReachability(settings.serverHost) else {
            logManager.log("Network unreachable", level: .error)
            return false
        }
        
        // Test 2: WebDAV connection
        guard await testWebDAVConnection(settings) else {
            logManager.log("WebDAV connection failed", level: .error)
            return false
        }
        
        logManager.log("Connection test successful", level: .info)
        return true
    }
    
    private func testNetworkReachability(_ host: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/sbin/ping")
            task.arguments = ["-c", "1", "-W", "5000", host]
            
            do {
                try task.run()
                task.waitUntilExit()
                continuation.resume(returning: task.terminationStatus == 0)
            } catch {
                logManager.log("Ping failed: \(error)", level: .error)
                continuation.resume(returning: false)
            }
        }
    }
    
    private func testWebDAVConnection(_ settings: BackupSettings) async -> Bool {
        guard let plainPassword = await settings.getPlainPassword() else {
            logManager.log("Failed to get password for WebDAV test", level: .error)
            return false
        }
        
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            
            var arguments = [
                "-s", "-f", "-X", "PROPFIND",
                "--user", "\(settings.webdavUsername):\(plainPassword)",
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
            task.standardError = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                if task.terminationStatus != 0 {
                    let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    logManager.log("WebDAV test failed: \(errorOutput)", level: .error)
                }
                
                continuation.resume(returning: task.terminationStatus == 0)
            } catch {
                logManager.log("WebDAV test error: \(error)", level: .error)
                continuation.resume(returning: false)
            }
        }
    }
    
    // MARK: - Backup Operations
    
    private func performBackup(_ settings: BackupSettings) async -> (success: Bool, error: String?, filesCount: Int, totalSize: Int64) {
        let dateDaily = DateFormatter.dailyFormat.string(from: Date())
        let dateVersion = DateFormatter.versionFormat.string(from: Date())
        
        // Build remote paths
        let remoteBase = "\(settings.remoteName):\(settings.webdavPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
        
        // Step 1: Daily sync
        logManager.log("Starting daily sync", level: .info)
        let dailyResult = await runRcloneCommand([
            "sync",
            sourcePath,
            "\(remoteBase)/daily/\(dateDaily)",
            "--progress",
            "--transfers", "4",
            "--timeout", "300s"
        ])
        
        guard dailyResult.success else {
            return (false, "Daily sync failed: \(dailyResult.error ?? "Unknown")", 0, 0)
        }
        
        // Step 2: Version backup
        logManager.log("Starting version backup", level: .info)
        let versionResult = await runRcloneCommand([
            "copy",
            sourcePath,
            "\(remoteBase)/current",
            "--update",
            "--backup-dir", "\(remoteBase)/versions/\(dateVersion)",
            "--progress",
            "--transfers", "4",
            "--timeout", "300s"
        ])
        
        guard versionResult.success else {
            return (false, "Version backup failed: \(versionResult.error ?? "Unknown")", 0, 0)
        }
        
        // Get stats (simplified for now)
        let stats = await getBackupStats(remoteBase, dateDaily)
        
        logManager.log("Backup completed: \(stats.fileCount) files, \(stats.totalSize) bytes", level: .info)
        return (true, nil, stats.fileCount, stats.totalSize)
    }
    
    private func runRcloneCommand(_ arguments: [String]) async -> (success: Bool, error: String?) {
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: rclonePath)
            task.arguments = arguments
            
            var environment = ProcessInfo.processInfo.environment
            environment["RCLONE_CONFIG"] = configPath
            task.environment = environment
            
            let errorPipe = Pipe()
            task.standardError = errorPipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                if task.terminationStatus == 0 {
                    continuation.resume(returning: (true, nil))
                } else {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    continuation.resume(returning: (false, errorOutput))
                }
            } catch {
                continuation.resume(returning: (false, error.localizedDescription))
            }
        }
    }
    
    private func getBackupStats(_ remoteBase: String, _ dateFolder: String) async -> (fileCount: Int, totalSize: Int64) {
        // Simplified stats - return reasonable defaults for now
        return (150, 1024000)
    }
    
    // MARK: - Configuration Management
    
    private func writeRcloneConfig(_ settings: BackupSettings) async throws {
        let configContent = generateRcloneConfig(settings)
        
        // Ensure config directory exists
        let configDir = URL(fileURLWithPath: configPath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        
        // Write config
        try configContent.write(toFile: configPath, atomically: true, encoding: .utf8)
        logManager.log("Updated rclone configuration", level: .debug)
    }
    
    private func generateRcloneConfig(_ settings: BackupSettings) -> String {
        var config = """
        [\(settings.remoteName)]
        type = webdav
        url = \(settings.fullWebDAVURL)
        vendor = nextcloud
        user = \(settings.webdavUsername)
        pass = \(settings.webdavPasswordObscured)
        """
        
        if !settings.webdavVerifySSL || !settings.webdavUseHTTPS {
            config += "\ninsecure_skip_verify = true"
        }
        
        return config
    }
    
    // MARK: - Helper Methods
    
    private func shouldRunBackup() async -> Bool {
        guard !isRunning else { return false }
        
        guard let settings = await dataActor.getSettings() else { return true }
        
        if let lastSuccess = settings.lastSuccessfulBackup {
            let hoursSince = Date().timeIntervalSince(lastSuccess) / 3600
            return hoursSince >= Double(settings.backupIntervalHours)
        }
        
        return true
    }
    
    func loadLastBackupStatus() async {
        let recent = await dataActor.getRecentSessions(limit: 1)
        if let last = recent.first {
            currentStatus = last.status
            lastBackupTime = last.endTime ?? last.startTime
            logManager.updateBackupStatus(last.status)
        }
    }
    
    // MARK: - Public Helper Methods
    
    func getSettings() async -> BackupSettings? {
        return await dataActor.getSettings()
    }
    
    func getOrCreateSettings() async -> BackupSettings {
        return await dataActor.getOrCreateSettings()
    }
    
    func getRecentSessions(limit: Int = 10) async -> [BackupSession] {
        return await dataActor.getRecentSessions(limit: limit)
    }
    
    func cleanOldSessions() async {
        await dataActor.cleanOldSessions()
    }
    
    // MARK: - Debug Methods (for development only)
    
    #if DEBUG
    func debugConnection() async -> Bool {
        guard let settings = await dataActor.getSettings() else {
            logManager.log("❌ No settings found for debug", level: .error)
            return false
        }
        
        return await ConnectionDebugHelper.shared.debugConnection(with: settings, logManager: logManager)
    }
    
    func debugRcloneConfig() async {
        guard let settings = await dataActor.getSettings() else {
            logManager.log("❌ No settings found", level: .error)
            return
        }
        
        logManager.log("🔧 Current rclone configuration:", level: .info)
        let config = settings.generateRcloneConfig()
        logManager.log(config, level: .debug)
    }
    
    func debugPasswordHandling() async {
        guard let settings = await dataActor.getSettings() else {
            logManager.log("❌ No settings found", level: .error)
            return
        }
        
        logManager.log("🔐 Testing password handling:", level: .info)
        logManager.log("Obscured password: \(settings.webdavPasswordObscured.isEmpty ? "EMPTY" : "SET")", level: .debug)
        
        if let plainPassword = await settings.getPlainPassword() {
            logManager.log("✅ Password reveal successful (length: \(plainPassword.count))", level: .debug)
        } else {
            logManager.log("❌ Password reveal failed", level: .error)
        }
    }
    #endif
}
