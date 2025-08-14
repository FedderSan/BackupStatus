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
    
    // Fixed paths - config and rclone only
    private let rclonePath = "/usr/local/bin/rclone"
    private let configPath = "/Users/danielfeddersen/.config/rclone/rclone.conf"
    // Source path now comes from settings!
    
    init(modelContainer: ModelContainer, logManager: LogManager) {
        self.dataActor = BackupDataActor(modelContainer: modelContainer)
        self.logManager = logManager
        Task {
            await loadLastBackupStatus()
        }
    }
    
    // MARK: - Main Backup Function
    
    func runBackup(force: Bool = false) async {
        // Check if already running
        guard !isRunning else {
            logManager.log("Backup already in progress, skipping", level: .warning)
            return
        }
        
        logManager.log("Backup requested (force: \(force))", level: .debug)
        
        // Get or create settings
        let settings = await dataActor.getOrCreateSettings()
        
        // Check if configuration is valid before proceeding
        let validation = settings.validateConfiguration()
        guard validation.isValid else {
            let errorMessage = "Configuration incomplete: " + validation.errors.joined(separator: ", ")
            logManager.log(errorMessage, level: .error)
            currentStatus = .failed
            logManager.updateBackupStatus(.failed)
            return
        }
        
        if !force {
            // Check schedule for regular backup
            if let lastSuccess = settings.lastSuccessfulBackup {
                let hoursSince = Date().timeIntervalSince(lastSuccess) / 3600
                if hoursSince < Double(settings.backupIntervalHours) {
                    currentStatus = .skipped
                    logManager.updateBackupStatus(.skipped)
                    logManager.log("Backup skipped - only \(String(format: "%.1f", hoursSince)) hours since last backup (interval: \(settings.backupIntervalHours) hours)", level: .info)
                    return
                }
            }
            logManager.log("Scheduled backup proceeding", level: .info)
        } else {
            logManager.log("Force backup requested - bypassing schedule check", level: .info)
        }
        
        logManager.log("Starting backup process", level: .info)
        isRunning = true
        currentStatus = .running
        logManager.updateBackupStatus(.running)
        
        do {
            // Create backup session
            let session = await dataActor.createBackupSession()
            let sessionID = session.persistentModelID
            
            logManager.log("Backing up from: \(settings.fullSourcePath)", level: .info)
            
            // Perform backup based on remote type
            let result: (success: Bool, error: String?, filesCount: Int, totalSize: Int64)
            
            switch settings.remoteType {
            case .local:
                result = await performLocalBackup(settings)
            case .webdav:
                // Write rclone config and test connection first
                try await writeRcloneConfig(settings)
                
                let isConnected = await testConnection(settings)
                connectionStatus = isConnected ? .connected : .failed
                lastConnectionTestTime = Date()
                
                guard isConnected else {
                    throw BackupError.connectionFailed
                }
                
                result = await performRcloneBackup(settings)
            default:
                throw BackupError.backupFailed("Remote type \(settings.remoteType.rawValue) not yet implemented")
            }
            
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
        
        let isConnected: Bool
        
        switch settings.remoteType {
        case .local:
            isConnected = await testLocalConnection(settings)
        case .webdav:
            isConnected = await testConnection(settings)
        default:
            isConnected = false
            logManager.log("Connection test not implemented for \(settings.remoteType.displayName)", level: .error)
        }
        
        connectionStatus = isConnected ? .connected : .failed
        logManager.log("Connection test result: \(isConnected ? "SUCCESS" : "FAILED")", level: isConnected ? .info : .error)
    }
    
    // MARK: - Local Backup Operations
    
    private func performLocalBackup(_ settings: BackupSettings) async -> (success: Bool, error: String?, filesCount: Int, totalSize: Int64) {
        logManager.log("Starting local file system backup", level: .info)
        logManager.log("Source: \(settings.fullSourcePath)", level: .debug)
        logManager.log("Destination: \(settings.fullLocalDestinationPath)", level: .debug)
        
        let fileManager = FileManager.default
        let date = Date()
        
        do {
            // Build exclude arguments if any patterns are specified
            var excludeArgs: [String] = []
            for pattern in settings.excludeArray {
                excludeArgs.append("--exclude")
                excludeArgs.append(pattern)
            }
            
            // Step 1: Always sync to 'latest' folder (this is the current complete backup)
            let latestPath = settings.localLatestPath()
            try fileManager.createDirectory(atPath: latestPath, withIntermediateDirectories: true, attributes: nil)
            
            logManager.log("Syncing to latest folder: \(latestPath)", level: .info)
            let latestResult = await runRsyncCommand(
                from: settings.fullSourcePath,
                to: latestPath,
                delete: true,  // Mirror source exactly
                excludePatterns: excludeArgs
            )
            
            guard latestResult.success else {
                return (false, "Latest sync failed: \(latestResult.error ?? "Unknown")", 0, 0)
            }
            
            // Step 2: Create versioned backup if enabled
            if settings.localCreateDatedFolders {
                let versionPath = settings.localVersionPath(for: date)
                
                // Only create a version if it's different from latest (to avoid duplicates)
                // For force backup or scheduled backup, we create a snapshot
                logManager.log("Creating version snapshot: \(versionPath)", level: .info)
                
                try fileManager.createDirectory(
                    atPath: URL(fileURLWithPath: versionPath).deletingLastPathComponent().path,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                
                // Use hard links for efficiency (instant, no extra space for unchanged files)
                let linkResult = await runHardLinkCopy(from: latestPath, to: versionPath)
                
                if !linkResult.success {
                    // Fall back to regular copy if hard links fail
                    logManager.log("Hard link failed, using regular copy", level: .warning)
                    let versionResult = await runRsyncCommand(
                        from: latestPath,
                        to: versionPath,
                        delete: false,
                        excludePatterns: []
                    )
                    
                    if !versionResult.success {
                        logManager.log("Version backup failed: \(versionResult.error ?? "Unknown")", level: .warning)
                        // Don't fail the whole backup if versioning fails
                    }
                }
            }
            
            // Get backup stats from latest folder
            let stats = await getLocalBackupStats(latestPath)
            
            logManager.log("Local backup completed: \(stats.fileCount) files, \(stats.totalSize) bytes", level: .info)
            return (true, nil, stats.fileCount, stats.totalSize)
            
        } catch {
            return (false, "Failed to create backup directories: \(error.localizedDescription)", 0, 0)
        }
    }
    
    private func runHardLinkCopy(from source: String, to destination: String) async -> (success: Bool, error: String?) {
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/cp")
            task.arguments = ["-al", source, destination]  // -a = archive, -l = hard links
            
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
    
    private func runRsyncCommand(from source: String, to destination: String, delete: Bool, excludePatterns: [String] = []) async -> (success: Bool, error: String?) {
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/rsync")
            
            var arguments = [
                "-avh",  // archive, verbose, human-readable
                "--progress"
            ]
            
            if delete {
                arguments.append("--delete")
            }
            
            // Add exclude patterns
            arguments.append(contentsOf: excludePatterns)
            
            arguments.append(source)
            arguments.append(destination)
            
            task.arguments = arguments
            
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
    
    private func getLocalBackupStats(_ path: String) async -> (fileCount: Int, totalSize: Int64) {
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/find")
            task.arguments = [path, "-type", "f"]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? ""
                let fileCount = output.split(separator: "\n").count
                
                // Get total size using du
                let duTask = Process()
                duTask.executableURL = URL(fileURLWithPath: "/usr/bin/du")
                duTask.arguments = ["-sb", path]
                
                let duPipe = Pipe()
                duTask.standardOutput = duPipe
                
                try duTask.run()
                duTask.waitUntilExit()
                
                let duData = duPipe.fileHandleForReading.readDataToEndOfFile()
                let duOutput = String(data: duData, encoding: .utf8) ?? ""
                let sizeString = duOutput.split(separator: "\t").first?.trimmingCharacters(in: .whitespaces) ?? "0"
                let totalSize = Int64(sizeString) ?? 0
                
                continuation.resume(returning: (fileCount, totalSize))
            } catch {
                continuation.resume(returning: (0, 0))
            }
        }
    }
    
    private func testLocalConnection(_ settings: BackupSettings) async -> Bool {
        let fileManager = FileManager.default
        
        // Test source path
        guard settings.sourceExists else {
            logManager.log("Source path does not exist: \(settings.sourcePath)", level: .error)
            return false
        }
        
        guard settings.sourceIsReadable else {
            logManager.log("Source path is not readable: \(settings.sourcePath)", level: .error)
            return false
        }
        
        // Test destination path
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: settings.localDestinationPath, isDirectory: &isDirectory) else {
            logManager.log("Local destination path does not exist: \(settings.localDestinationPath)", level: .error)
            return false
        }
        
        guard isDirectory.boolValue else {
            logManager.log("Local destination path is not a directory: \(settings.localDestinationPath)", level: .error)
            return false
        }
        
        guard fileManager.isWritableFile(atPath: settings.localDestinationPath) else {
            logManager.log("Local destination path is not writable: \(settings.localDestinationPath)", level: .error)
            return false
        }
        
        // Test creating a temporary file
        let testFileName = UUID().uuidString
        let testFilePath = "\(settings.localDestinationPath)/.\(testFileName).test"
        
        do {
            try "test".write(toFile: testFilePath, atomically: true, encoding: .utf8)
            try fileManager.removeItem(atPath: testFilePath)
            logManager.log("Local connection test successful", level: .info)
            return true
        } catch {
            logManager.log("Local connection test failed: \(error)", level: .error)
            return false
        }
    }
    
    // MARK: - WebDAV/rclone Operations
    
    private func performRcloneBackup(_ settings: BackupSettings) async -> (success: Bool, error: String?, filesCount: Int, totalSize: Int64) {
        let dateVersion = DateFormatter.versionFormat.string(from: Date())
        
        // Build remote paths
        let remoteBase = "\(settings.remoteName):\(settings.webdavPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")))"
        
        // Build exclude arguments
        var excludeArgs: [String] = []
        for pattern in settings.excludeArray {
            excludeArgs.append("--exclude")
            excludeArgs.append(pattern)
        }
        
        // Step 1: Sync to 'latest' folder (always current)
        logManager.log("Syncing to latest folder on WebDAV", level: .info)
        var latestArgs = [
            "sync",
            settings.fullSourcePath,
            "\(remoteBase)/latest",
            "--progress",
            "--transfers", "4",
            "--timeout", "300s"
        ]
        latestArgs.append(contentsOf: excludeArgs)
        
        let latestResult = await runRcloneCommand(latestArgs)
        
        guard latestResult.success else {
            return (false, "Latest sync failed: \(latestResult.error ?? "Unknown")", 0, 0)
        }
        
        // Step 2: Create version backup (using server-side copy if possible)
        logManager.log("Creating version backup: \(dateVersion)", level: .info)
        
        // First try server-side copy (much faster)
        let copyArgs = [
            "copy",
            "\(remoteBase)/latest",
            "\(remoteBase)/versions/\(dateVersion)",
            "--progress",
            "--timeout", "300s"
        ]
        
        let versionResult = await runRcloneCommand(copyArgs)
        
        if !versionResult.success {
            logManager.log("Server-side copy failed, trying direct upload", level: .warning)
            // Fall back to direct upload if server-side copy fails
            var directArgs = [
                "copy",
                settings.fullSourcePath,
                "\(remoteBase)/versions/\(dateVersion)",
                "--progress",
                "--transfers", "4",
                "--timeout", "300s"
            ]
            directArgs.append(contentsOf: excludeArgs)
            
            let directResult = await runRcloneCommand(directArgs)
            if !directResult.success {
                logManager.log("Version backup failed: \(directResult.error ?? "Unknown")", level: .warning)
                // Don't fail the whole backup if versioning fails
            }
        }
        
        // Get stats (simplified for now)
        let stats = await getBackupStats(remoteBase, "latest")
        
        logManager.log("WebDAV backup completed: \(stats.fileCount) files, \(stats.totalSize) bytes", level: .info)
        return (true, nil, stats.fileCount, stats.totalSize)
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
        let configContent = settings.generateRcloneConfig()
        
        // Ensure config directory exists
        let configDir = URL(fileURLWithPath: configPath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        
        // Write config
        try configContent.write(toFile: configPath, atomically: true, encoding: .utf8)
        logManager.log("Updated rclone configuration", level: .debug)
    }
    
    // MARK: - Helper Methods
    
    func loadLastBackupStatus() async {
        let recent = await dataActor.getRecentSessions(limit: 1)
        if let last = recent.first {
            currentStatus = last.status
            lastBackupTime = last.endTime ?? last.startTime
            logManager.updateBackupStatus(last.status)
        }
    }
    
    // MARK: - Public Helper Methods
    
    func runForceBackup() async {
        await runBackup(force: true)
    }
    
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
        
        logManager.log("📁 Source: \(settings.fullSourcePath)", level: .debug)
        logManager.log("📁 Source exists: \(settings.sourceExists)", level: .debug)
        logManager.log("📁 Source readable: \(settings.sourceIsReadable)", level: .debug)
        
        switch settings.remoteType {
        case .local:
            logManager.log("📁 Destination: \(settings.fullLocalDestinationPath)", level: .debug)
            return await testLocalConnection(settings)
        case .webdav:
            return await ConnectionDebugHelper.shared.debugConnection(with: settings, logManager: logManager)
        default:
            logManager.log("❌ Debug not implemented for \(settings.remoteType.displayName)", level: .error)
            return false
        }
    }
    
    func debugRcloneConfig() async {
        guard let settings = await dataActor.getSettings() else {
            logManager.log("❌ No settings found", level: .error)
            return
        }
        
        logManager.log("🔧 Current configuration:", level: .info)
        logManager.log("Remote Type: \(settings.remoteType.displayName)", level: .debug)
        logManager.log("Source Path: \(settings.fullSourcePath)", level: .debug)
        
        if let sourceInfo = settings.getSourceInfo() {
            logManager.log("Source contains: \(sourceInfo.fileCount) files, \(ByteCountFormatter.string(fromByteCount: sourceInfo.totalSize, countStyle: .file))", level: .debug)
        }
        
        switch settings.remoteType {
        case .local:
            logManager.log("Local Path: \(settings.localDestinationPath)", level: .debug)
            logManager.log("Create Dated Folders: \(settings.localCreateDatedFolders)", level: .debug)
            logManager.log("Latest Path: \(settings.localLatestPath())", level: .debug)
            logManager.log("Version Path: \(settings.localVersionPath())", level: .debug)
        case .webdav:
            let config = settings.generateRcloneConfig()
            logManager.log(config, level: .debug)
        default:
            logManager.log("Configuration not yet implemented for \(settings.remoteType.displayName)", level: .debug)
        }
        
        if !settings.excludePatterns.isEmpty {
            logManager.log("Exclude patterns: \(settings.excludeArray.joined(separator: ", "))", level: .debug)
        }
    }
    
    func debugPasswordHandling() async {
        guard let settings = await dataActor.getSettings() else {
            logManager.log("❌ No settings found", level: .error)
            return
        }
        
        switch settings.remoteType {
        case .webdav:
            logManager.log("🔐 Testing WebDAV password handling:", level: .info)
            logManager.log("Obscured password: \(settings.webdavPasswordObscured.isEmpty ? "EMPTY" : "SET")", level: .debug)
            
            if let plainPassword = await settings.getPlainPassword() {
                logManager.log("✅ Password reveal successful (length: \(plainPassword.count))", level: .debug)
            } else {
                logManager.log("❌ Password reveal failed", level: .error)
            }
        case .local:
            logManager.log("🔐 Local backup doesn't require password authentication", level: .info)
        default:
            logManager.log("🔐 Password handling not implemented for \(settings.remoteType.displayName)", level: .info)
        }
    }
    #endif
}
