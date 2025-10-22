import Foundation
import SwiftData

@MainActor
class BackupManager: ObservableObject {
    @Published var currentStatus: BackupStatus = .success
    @Published var connectionStatus: ConnectionStatus = .unknown
    @Published var lastBackupTime: Date?
    @Published var lastConnectionTestTime: Date?
    @Published var isRunning = false
    
    let dataActor: BackupDataActor
    let logManager: LogManager
    
    // Add initialization state tracking
    @Published var isInitialized = false
    private var initializationTask: Task<Void, Never>?
    
    // Add debouncing to prevent rapid UI updates
    var statusUpdateTask: Task<Void, Never>?
    
    // FIXED: Dynamic paths instead of hardcoded ones
    var rclonePath: String {
        // Try common locations for rclone
        let possiblePaths = [
            "/usr/local/bin/rclone",
            "/opt/homebrew/bin/rclone",
            "/usr/bin/rclone"
        ]
        
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        
        // If not found in common locations, try using 'which' command
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        task.arguments = ["rclone"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let path = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
                   !path.isEmpty {
                    return path
                }
            }
        } catch {
            logManager.log("Failed to find rclone path: \(error)", level: .error)
        }
        
        // Fallback to default
        return "/usr/local/bin/rclone"
    }
    
    var configPath: String {
        // Use user's home directory instead of hardcoded path
        let homeDirectory = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(homeDirectory)/.config/rclone/rclone.conf"
    }
    
    init(modelContainer: ModelContainer, logManager: LogManager) {
        self.dataActor = BackupDataActor(modelContainer: modelContainer)
        self.logManager = logManager
        
        // Initialize asynchronously with proper error handling
        initializationTask = Task { @MainActor in
            await performInitialization()
        }
    }
    
    deinit {
        initializationTask?.cancel()
        statusUpdateTask?.cancel()
    }
    
    
    
    
    
    // MARK: - Main Backup Function
    
    func runBackup(force: Bool = false) async {
        // Wait for initialization to complete
        _ = await initializationTask?.result
        
        guard isInitialized else {
            logManager.log("❌ Cannot run backup: BackupManager not initialized", level: .error)
            return
        }
        
        logManager.log("🚀 runBackup called with force=\(force)", level: .info)
        
        // Ensure we're on main actor for UI updates
        await MainActor.run {
            guard !isRunning else {
                logManager.log("Backup already in progress, skipping", level: .warning)
                return
            }
            
            logManager.log("Backup requested (force: \(force))", level: .debug)
            isRunning = true
        }
        
        // Check if external tools exist
        if !FileManager.default.fileExists(atPath: rclonePath) {
            logManager.log("❌ rclone not found at: \(rclonePath)", level: .error)
            await MainActor.run {
                currentStatus = .failed
                isRunning = false
            }
            return
        }
        
        // Update status safely
        updateStatus(.running, debounce: false)
        
        // Get or create settings
        let settings = await dataActor.getOrCreateSettings()
        
        // Check if configuration is valid before proceeding
        let validation = settings.validateConfiguration()
        guard validation.isValid else {
            let errorMessage = "Configuration incomplete: " + validation.errors.joined(separator: ", ")
            logManager.log(errorMessage, level: .error)
            
            await MainActor.run {
                currentStatus = .failed
                isRunning = false
                lastBackupTime = Date()
            }
            updateStatus(.failed)
            return
        }
        
        logManager.log("✅ Configuration valid, proceeding with backup", level: .info)
        logManager.log("📁 Source: \(settings.fullSourcePath)", level: .info)
        logManager.log("🎯 Remote type: \(settings.remoteType.displayName)", level: .info)
        
        if !force {
            // Check schedule for regular backup
            if let lastSuccess = settings.lastSuccessfulBackup {
                let hoursSince = Date().timeIntervalSince(lastSuccess) / 3600
                if hoursSince < Double(settings.backupIntervalHours) {
                    await MainActor.run {
                        currentStatus = .skipped
                        isRunning = false
                        lastBackupTime = Date()
                    }
                    updateStatus(.skipped)
                    logManager.log("Backup skipped - only \(String(format: "%.1f", hoursSince)) hours since last backup (interval: \(settings.backupIntervalHours) hours)", level: .info)
                    return
                }
            }
            logManager.log("Scheduled backup proceeding", level: .info)
        } else {
            logManager.log("🔥 Force backup requested - bypassing schedule check", level: .info)
        }
        
        logManager.log("Starting backup process", level: .info)
        
        do {
            // Create backup session
            let session = await dataActor.createBackupSession()
            let sessionID = session.persistentModelID
            
            logManager.log("📦 Created backup session: \(sessionID)", level: .debug)
            
            // Perform backup based on remote type
            let result: (success: Bool, error: String?, filesCount: Int, totalSize: Int64)
            
            switch settings.remoteType {
            case .local:
                logManager.log("🏠 Starting local backup", level: .info)
                result = await performLocalBackup(settings)
            case .webdav:
                logManager.log("☁️ Starting WebDAV backup", level: .info)
                // Write rclone config and test connection first
                do {
                    try await writeRcloneConfig(settings)
                    logManager.log("📝 rclone config written", level: .debug)
                } catch {
                    logManager.log("❌ Failed to write rclone config: \(error)", level: .error)
                    throw BackupError.backupFailed("Failed to write rclone config: \(error)")
                }
                
                let isConnected = await testConnection(settings)
                updateConnectionStatus(isConnected ? .connected : .failed)
                
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
                
                await MainActor.run {
                    currentStatus = .success
                    isRunning = false
                    lastBackupTime = Date()
                }
                updateStatus(.success)
                logManager.log("✅ Backup completed successfully: \(result.filesCount) files, \(ByteCountFormatter.string(fromByteCount: result.totalSize, countStyle: .file))", level: .info)
            } else {
                try await dataActor.updateSession(sessionID,
                                                success: false,
                                                error: result.error,
                                                filesCount: 0,
                                                totalSize: 0)
                await MainActor.run {
                    currentStatus = .failed
                    isRunning = false
                    lastBackupTime = Date()
                }
                updateStatus(.failed)
                logManager.log("❌ Backup failed: \(result.error ?? "Unknown error")", level: .error)
            }
            
        } catch {
            logManager.log("💥 Backup error: \(error)", level: .error)
            await MainActor.run {
                currentStatus = .failed
                isRunning = false
                lastBackupTime = Date()
            }
            updateStatus(.failed)
        }
    }
    
    // MARK: - Connection Testing
    
    func runConnectionTest() async {
        logManager.log("Starting connection test", level: .info)
        updateConnectionStatus(.testing)
        
        guard let settings = await dataActor.getSettings() else {
            updateConnectionStatus(.failed)
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
        
        updateConnectionStatus(isConnected ? .connected : .failed)
        logManager.log("Connection test result: \(isConnected ? "SUCCESS" : "FAILED")", level: isConnected ? .info : .error)
    }
    
    // MARK: - Local Backup Operations (FIXED FOR ICLOUD COMPATIBILITY)
    
    private func performLocalBackup(_ settings: BackupSettings) async -> (success: Bool, error: String?, filesCount: Int, totalSize: Int64) {
        logManager.log("Starting local file system backup", level: .info)
        logManager.log("Source: \(settings.fullSourcePath)", level: .debug)
        logManager.log("Destination: \(settings.fullLocalDestinationPath)", level: .debug)
        
        let fileManager = FileManager.default
        let date = Date()
        
        // Check if destination is in iCloud Drive
        let isICloudPath = settings.fullLocalDestinationPath.contains("Library/Mobile Documents/com~apple~CloudDocs")
        if isICloudPath {
            logManager.log("📱 iCloud Drive destination detected - using iCloud-compatible settings", level: .info)
        }
        
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
            
            // CRITICAL FIX: For iCloud destinations, don't preserve timestamps
            // This makes files appear "new" so iCloud uploads them
            let latestResult = await runRsyncCommand(
                from: settings.fullSourcePath,
                to: latestPath,
                delete: true,
                excludePatterns: excludeArgs,
                preserveTimestamps: !isICloudPath  // Don't preserve timestamps for iCloud!
            )
            
            guard latestResult.success else {
                return (false, "Latest sync failed: \(latestResult.error ?? "Unknown")", 0, 0)
            }
            
            // CRITICAL FIX: Set proper permissions AFTER rsync completes
            // This must be done after rsync because rsync preserves source permissions
            if isICloudPath {
                logManager.log("📱 Fixing permissions for iCloud compatibility", level: .debug)
                await fixICloudPermissions(at: latestPath)
            }
            
            // Step 2: Create versioned backup if enabled
            if settings.localCreateDatedFolders {
                let versionPath = settings.localVersionPath(for: date)
                
                logManager.log("Creating version snapshot: \(versionPath)", level: .info)
                
                try fileManager.createDirectory(
                    atPath: URL(fileURLWithPath: versionPath).deletingLastPathComponent().path,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                
                // Set proper permissions for versions directory
                let versionsDir = URL(fileURLWithPath: versionPath).deletingLastPathComponent().path
                try? fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: versionsDir)
                
                // CRITICAL: Add trailing slash so rsync copies CONTENTS, not the directory itself
                let sourceWithSlash = latestPath.hasSuffix("/") ? latestPath : "\(latestPath)/"
                
                // SIMPLE FIX: Choose method based on destination type
                if isICloudPath {
                    // ☁️ iCloud Drive: Use regular copy (NO hard links)
                    logManager.log("☁️ iCloud destination - using regular copy (no hard links)", level: .info)
                    
                    let versionResult = await runRsyncCommand(
                        from: sourceWithSlash,  // ✅ With trailing slash!
                        to: versionPath,
                        delete: false,
                        excludePatterns: [],
                        preserveTimestamps: false  // Use CURRENT time so iCloud sees files as "new"
                    )
                    
                    if versionResult.success {
                        logManager.log("✅ Version created with independent files (iCloud-compatible)", level: .info)
                    } else {
                        logManager.log("❌ Version backup failed: \(versionResult.error ?? "Unknown")", level: .warning)
                    }
                    
                    // Fix permissions for iCloud
                    await fixICloudPermissions(at: versionPath)
                    
                } else {
                    // 💾 Non-iCloud: Use efficient hard links (saves space)
                    logManager.log("💾 Non-iCloud destination - using space-efficient hard links", level: .info)
                    
                    let linkResult = await runHardLinkCopy(from: latestPath, to: versionPath)
                    
                    if linkResult.success {
                        logManager.log("✅ Version created with hard links (space-efficient)", level: .info)
                    } else {
                        // Fallback to regular copy
                        logManager.log("⚠️ Hard link failed, using regular copy", level: .warning)
                        
                        let versionResult = await runRsyncCommand(
                            from: sourceWithSlash,  // ✅ With trailing slash!
                            to: versionPath,
                            delete: false,
                            excludePatterns: [],
                            preserveTimestamps: true  // Preserve original timestamps for non-iCloud
                        )
                        
                        if !versionResult.success {
                            logManager.log("❌ Version backup failed: \(versionResult.error ?? "Unknown")", level: .warning)
                        }
                    }
                }
                
                // Clean up old versions after creating new one
                await cleanupOldVersions(settings)
            }
            
            if isICloudPath {
                logManager.log("📱 iCloud Drive backup complete - files should upload automatically", level: .info)
                logManager.log("💡 Check iCloud.com in a few minutes to verify upload", level: .info)
            }
            
            // Get backup stats from latest folder
            let stats = await getLocalBackupStats(latestPath)
            
            logManager.log("Local backup completed: \(stats.fileCount) files, \(stats.totalSize) bytes", level: .info)
            return (true, nil, stats.fileCount, stats.totalSize)
            
        } catch {
            return (false, "Failed to create backup directories: \(error.localizedDescription)", 0, 0)
        }
    }
    
    // MARK: - iCloud Permission Fix
    
    /// Fixes permissions recursively for iCloud compatibility
    /// Must be called AFTER rsync to override source permissions
    private func fixICloudPermissions(at path: String) async {
        await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/find")
            
            // Find all directories and set to 755 (rwxr-xr-x)
            // Find all files and set to 644 (rw-r--r--)
            // This makes everything readable by iCloud daemon
            task.arguments = [
                path,
                "(",
                "-type", "d", "-exec", "chmod", "755", "{}", ";",
                ")",
                "-o",
                "(",
                "-type", "f", "-exec", "chmod", "644", "{}", ";",
                ")"
            ]
            
            do {
                try task.run()
                task.waitUntilExit()
                
                if task.terminationStatus == 0 {
                    Task { @MainActor in
                        self.logManager.log("✅ Fixed permissions for iCloud sync", level: .debug)
                    }
                } else {
                    Task { @MainActor in
                        self.logManager.log("⚠️ Some permissions could not be fixed", level: .warning)
                    }
                }
            } catch {
                Task { @MainActor in
                    self.logManager.log("❌ Error fixing permissions: \(error)", level: .error)
                }
            }
            
            continuation.resume()
        }
    }
    
    // MARK: - Version Cleanup Methods
    
    private func cleanupOldVersions(_ settings: BackupSettings) async {
        guard settings.shouldCleanupVersions() else {
            logManager.log("🗂️ Version cleanup disabled - keeping all versions", level: .debug)
            return
        }
        
        let versionsToDelete = settings.getVersionsToCleanup()
        guard !versionsToDelete.isEmpty else {
            let existingCount = settings.getExistingVersions().count
            let maxVersions = settings.backupVersionRetention.rawValue
            logManager.log("🗂️ Version cleanup: \(existingCount)/\(maxVersions) versions - no cleanup needed", level: .debug)
            return
        }
        
        let versionsDir = settings.versionsDirectoryPath()
        var deletedCount = 0
        var failedCount = 0
        
        logManager.log("🗑️ Cleaning up \(versionsToDelete.count) old backup versions", level: .info)
        
        for versionName in versionsToDelete {
            let versionPath = "\(versionsDir)/\(versionName)"
            
            do {
                // Get size before deletion for reporting
                let attributes = try FileManager.default.attributesOfItem(atPath: versionPath)
                let size = attributes[.size] as? Int64 ?? 0
                
                // Delete the version directory
                try FileManager.default.removeItem(atPath: versionPath)
                
                deletedCount += 1
                logManager.log("🗑️ Deleted version: \(versionName) (\(ByteCountFormatter.string(fromByteCount: size, countStyle: .file)))", level: .debug)
                
            } catch {
                failedCount += 1
                logManager.log("❌ Failed to delete version \(versionName): \(error)", level: .error)
            }
        }
        
        let remainingCount = settings.getExistingVersions().count
        let retentionLimit = settings.backupVersionRetention.rawValue
        
        if deletedCount > 0 {
            logManager.log("✅ Version cleanup completed: deleted \(deletedCount) versions, \(remainingCount) remaining (limit: \(retentionLimit))", level: .info)
        }
        
        if failedCount > 0 {
            logManager.log("⚠️ Version cleanup had \(failedCount) failures", level: .warning)
        }
    }

    // MARK: - Manual Cleanup Method (for settings or manual triggers)

    func cleanupOldVersionsManually() async {
        let settings = await dataActor.getOrCreateSettings()
        
        logManager.log("🧹 Manual version cleanup requested", level: .info)
        logManager.log("📋 Current retention setting: \(settings.backupVersionRetention.displayName)", level: .info)
        
        await cleanupOldVersions(settings)
    }

    // MARK: - Version Statistics (for UI/debugging)

    func getVersionStatistics() async -> (totalVersions: Int, totalSize: Int64, oldestVersion: String?, newestVersion: String?) {
        let settings = await dataActor.getOrCreateSettings()
        let existingVersions = settings.getExistingVersions()
        
        guard !existingVersions.isEmpty else {
            return (0, 0, nil, nil)
        }
        
        let versionsDir = settings.versionsDirectoryPath()
        var totalSize: Int64 = 0
        
        for versionName in existingVersions {
            let versionPath = "\(versionsDir)/\(versionName)"
            if let attributes = try? FileManager.default.attributesOfItem(atPath: versionPath),
               let size = attributes[.size] as? Int64 {
                totalSize += size
            }
        }
        
        return (
            totalVersions: existingVersions.count,
            totalSize: totalSize,
            oldestVersion: existingVersions.first,
            newestVersion: existingVersions.last
        )
    }
    
    func runHardLinkCopy(from source: String, to destination: String) async -> (success: Bool, error: String?) {
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/cp")
            
            // Use "source/." to copy contents, not the directory itself
            let sourceWithDot = source.hasSuffix("/") ? "\(source)." : "\(source)/."
            
            task.arguments = ["-al", sourceWithDot, destination]  // -a = archive, -l = hard links
            
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
    
    
    
  
        
    private func updateConnectionStatus(_ status: ConnectionStatus) {
        Task { @MainActor in
            self.connectionStatus = status
            self.lastConnectionTestTime = Date()
        }
    }
    
    
    func migrateToProfiles() async {
        let settings = await dataActor.getOrCreateSettings()
        
        // Create a profile from existing settings
        let profile = BackupProfile(name: "Main Backup", profileType: .versioned)
        profile.sourcePath = settings.sourcePath
        profile.destinationPath = settings.localDestinationPath
        profile.excludePatterns = settings.excludePatterns
        profile.createVersions = settings.localCreateDatedFolders
        profile.versionRetentionCount = settings.backupVersionRetentionCount
        profile.backupIntervalHours = settings.backupIntervalHours
        
        let context = ModelContext(dataActor.modelContainer)
        context.insert(profile)
        try? context.save()
        
        logManager.log("✅ Migrated existing backup to profile system", level: .info)
    }
    
    
    
}
