//
//  BackupManager+Profiles.swift
//  BackupStatus
//
//  Multi-profile backup support
//

import Foundation

extension BackupManager {
    
    // MARK: - Profile Management
    
    func getAllProfiles() async -> [BackupProfile] {
        return await dataActor.getAllProfiles()
    }
    
    func getEnabledProfiles() async -> [BackupProfile] {
        return await dataActor.getEnabledProfiles()
    }
    
    func createProfile(name: String, type: BackupProfileType) async -> BackupProfile {
        let profile = await dataActor.createProfile(name: name, type: type)
        logManager.log("✅ Created new profile: \(name) (\(type.displayName))", level: .info)
        return profile
    }
    
    func deleteProfile(_ profile: BackupProfile) async {
        await dataActor.deleteProfile(profile)
        logManager.log("🗑️ Deleted profile: \(profile.name)", level: .info)
    }
    
    func updateProfileStats(_ profile: BackupProfile, filesCount: Int, totalSize: Int64) async {
        await dataActor.updateProfileStats(profile, filesCount: filesCount, totalSize: totalSize)
    }
    
    // MARK: - Run All Profiles
    
    func runAllProfileBackups(force: Bool = false) async {
        logManager.log("🚀 Running all enabled profile backups", level: .info)
        
        let profiles = await getEnabledProfiles()
        
        guard !profiles.isEmpty else {
            logManager.log("⚠️ No enabled profiles found", level: .warning)
            return
        }
        
        logManager.log("📋 Found \(profiles.count) enabled profile(s)", level: .info)
        
        for profile in profiles {
            logManager.log("▶️ Running profile: \(profile.name)", level: .info)
            await runProfileBackup(profile, force: force)
        }
        
        logManager.log("✅ All profile backups completed", level: .info)
    }
    
    // MARK: - Run Single Profile
    
    func runProfileBackup(_ profile: BackupProfile, force: Bool = false) async {
        guard profile.isEnabled else {
            logManager.log("⏭️ Skipping disabled profile: \(profile.name)", level: .info)
            return
        }
        
        logManager.log("🔄 Starting backup for profile: \(profile.name)", level: .info)
        logManager.log("📁 Source: \(profile.fullSourcePath)", level: .debug)
        logManager.log("🎯 Destination: \(profile.fullDestinationPath)", level: .debug)
        logManager.log("🔧 Type: \(profile.profileType.displayName)", level: .debug)
        
        // Validate configuration
        let validation = profile.validateConfiguration()
        guard validation.isValid else {
            let errorMessage = "Configuration invalid: " + validation.errors.joined(separator: ", ")
            logManager.log("❌ \(errorMessage)", level: .error)
            return
        }
        
        // Check schedule unless forced
        if !force {
            if let lastSuccess = profile.lastSuccessfulBackup {
                let hoursSince = Date().timeIntervalSince(lastSuccess) / 3600
                if hoursSince < Double(profile.backupIntervalHours) {
                    logManager.log("⏭️ Skipping \(profile.name) - only \(String(format: "%.1f", hoursSince)) hours since last backup", level: .info)
                    return
                }
            }
        }
        
        // Run backup based on profile type
        switch profile.profileType {
        case .versioned:
            await runVersionedBackup(profile)
        case .oneWaySync:
            await runOneWaySyncBackup(profile)
        }
    }
    
    // MARK: - Versioned Backup (existing logic adapted)
    
    private func runVersionedBackup(_ profile: BackupProfile) async {
        logManager.log("📦 Running versioned backup for: \(profile.name)", level: .info)
        
        let fileManager = FileManager.default
        let date = Date()
        
        do {
            // Build exclude arguments
            var excludeArgs: [String] = []
            for pattern in profile.excludeArray {
                excludeArgs.append("--exclude")
                excludeArgs.append(pattern)
            }
            
            // Step 1: Sync to 'latest' folder
            let latestPath = profile.latestPath()
            try fileManager.createDirectory(atPath: latestPath, withIntermediateDirectories: true, attributes: nil)
            
            logManager.log("Syncing to latest folder: \(latestPath)", level: .info)
            
            let latestResult = await runRsyncCommand(
                from: profile.fullSourcePath,
                to: latestPath,
                delete: true,
                excludePatterns: excludeArgs,
                preserveTimestamps: true
            )
            
            guard latestResult.success else {
                logManager.log("❌ Latest sync failed: \(latestResult.error ?? "Unknown")", level: .error)
                return
            }
            
            // Step 2: Create version if enabled
            if profile.createVersions {
                let versionPath = profile.versionPath(for: date)
                
                logManager.log("Creating version snapshot: \(versionPath)", level: .info)
                
                try fileManager.createDirectory(
                    atPath: URL(fileURLWithPath: versionPath).deletingLastPathComponent().path,
                    withIntermediateDirectories: true,
                    attributes: nil
                )
                
                let sourceWithSlash = latestPath.hasSuffix("/") ? latestPath : "\(latestPath)/"
                
                // Try hard link copy first
                let linkResult = await runHardLinkCopy(from: latestPath, to: versionPath)
                
                if !linkResult.success {
                    logManager.log("⚠️ Hard link failed, using regular copy", level: .warning)
                    
                    let versionResult = await runRsyncCommand(
                        from: sourceWithSlash,
                        to: versionPath,
                        delete: false,
                        excludePatterns: [],
                        preserveTimestamps: true
                    )
                    
                    if !versionResult.success {
                        logManager.log("❌ Version backup failed: \(versionResult.error ?? "Unknown")", level: .warning)
                    }
                }
                
                // Clean up old versions
                await cleanupProfileVersions(profile)
            }
            
            // Get stats and update profile
            let stats = await getLocalBackupStats(latestPath)
            await updateProfileStats(profile, filesCount: stats.fileCount, totalSize: stats.totalSize)
            
            logManager.log("✅ Versioned backup completed for \(profile.name): \(stats.fileCount) files, \(ByteCountFormatter.string(fromByteCount: stats.totalSize, countStyle: .file))", level: .info)
            
        } catch {
            logManager.log("❌ Versioned backup failed for \(profile.name): \(error)", level: .error)
        }
    }
    
    // MARK: - One-Way Sync Backup (NEW)
    
    private func runOneWaySyncBackup(_ profile: BackupProfile) async {
        logManager.log("🔄 Running one-way sync for: \(profile.name)", level: .info)
        
        let fileManager = FileManager.default
        let date = Date()
        
        do {
            // Build exclude arguments
            var excludeArgs: [String] = []
            for pattern in profile.excludeArray {
                excludeArgs.append("--exclude")
                excludeArgs.append(pattern)
            }
            
            // If using trash folder, exclude it from sync
            if profile.useTrashFolder {
                excludeArgs.append("--exclude")
                excludeArgs.append(profile.trashFolderName)
            }
            
            let destinationPath = profile.fullDestinationPath
            try fileManager.createDirectory(atPath: destinationPath, withIntermediateDirectories: true, attributes: nil)
            
            // Handle deletions with trash folder
            if profile.useTrashFolder {
                let trashPath = profile.trashPath()
                try fileManager.createDirectory(atPath: trashPath, withIntermediateDirectories: true, attributes: nil)
                
                // Create timestamped trash subdirectory
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                let trashTimestamp = dateFormatter.string(from: date)
                let trashSessionPath = "\(trashPath)/\(trashTimestamp)"
                
                logManager.log("🗑️ Using trash folder: \(trashSessionPath)", level: .debug)
                
                // Sync with --backup-dir to move deleted/changed files to trash
                let syncResult = await runRsyncWithTrash(
                    from: profile.fullSourcePath,
                    to: destinationPath,
                    trashDir: trashSessionPath,
                    excludePatterns: excludeArgs
                )
                
                guard syncResult.success else {
                    logManager.log("❌ One-way sync failed: \(syncResult.error ?? "Unknown")", level: .error)
                    return
                }
                
                // Clean up old trash if auto-empty is enabled
                if profile.shouldCleanupTrash() {
                    await cleanupProfileTrash(profile)
                }
                
            } else {
                // Regular sync with hard delete
                logManager.log("⚠️ Using hard delete (no trash folder)", level: .warning)
                
                let syncResult = await runRsyncCommand(
                    from: profile.fullSourcePath,
                    to: destinationPath,
                    delete: true,
                    excludePatterns: excludeArgs,
                    preserveTimestamps: true
                )
                
                guard syncResult.success else {
                    logManager.log("❌ One-way sync failed: \(syncResult.error ?? "Unknown")", level: .error)
                    return
                }
            }
            
            // Get stats and update profile
            let stats = await getLocalBackupStats(destinationPath)
            await updateProfileStats(profile, filesCount: stats.fileCount, totalSize: stats.totalSize)
            
            logManager.log("✅ One-way sync completed for \(profile.name): \(stats.fileCount) files, \(ByteCountFormatter.string(fromByteCount: stats.totalSize, countStyle: .file))", level: .info)
            
        } catch {
            logManager.log("❌ One-way sync failed for \(profile.name): \(error)", level: .error)
        }
    }
    
    // MARK: - rsync with Trash Support
    
    private func runRsyncWithTrash(
        from source: String,
        to destination: String,
        trashDir: String,
        excludePatterns: [String] = []
    ) async -> (success: Bool, error: String?) {
        let rsyncPath = "/usr/bin/rsync"
        guard FileManager.default.fileExists(atPath: rsyncPath) else {
            logManager.log("❌ rsync not found at: \(rsyncPath)", level: .error)
            return (false, "rsync not found")
        }
        
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: rsyncPath)
            
            var arguments = [
                "-avh",
                "--progress",
                "--delete",
                "--backup",
                "--backup-dir=\(trashDir)"
            ]
            
            // Add exclude patterns
            arguments.append(contentsOf: excludePatterns)
            
            arguments.append(source)
            arguments.append(destination)
            
            task.arguments = arguments
            
            let errorPipe = Pipe()
            task.standardError = errorPipe
            
            do {
                logManager.log("🔧 Running rsync with trash: \(trashDir)", level: .debug)
                try task.run()
                task.waitUntilExit()
                
                if task.terminationStatus == 0 {
                    continuation.resume(returning: (true, nil))
                } else {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    logManager.log("❌ rsync failed with code \(task.terminationStatus): \(errorOutput)", level: .error)
                    continuation.resume(returning: (false, errorOutput))
                }
            } catch {
                logManager.log("❌ rsync execution error: \(error)", level: .error)
                continuation.resume(returning: (false, error.localizedDescription))
            }
        }
    }
    
    // MARK: - Cleanup Methods
    
    private func cleanupProfileVersions(_ profile: BackupProfile) async {
        guard profile.shouldCleanupVersions() else {
            logManager.log("🗂️ Version cleanup disabled for \(profile.name)", level: .debug)
            return
        }
        
        let versionsToDelete = profile.getVersionsToCleanup()
        guard !versionsToDelete.isEmpty else {
            return
        }
        
        let versionsDir = profile.versionsDirectoryPath()
        var deletedCount = 0
        
        for versionName in versionsToDelete {
            let versionPath = "\(versionsDir)/\(versionName)"
            
            do {
                try FileManager.default.removeItem(atPath: versionPath)
                deletedCount += 1
                logManager.log("🗑️ Deleted old version: \(versionName)", level: .debug)
            } catch {
                logManager.log("❌ Failed to delete version \(versionName): \(error)", level: .error)
            }
        }
        
        if deletedCount > 0 {
            logManager.log("✅ Cleaned up \(deletedCount) old versions for \(profile.name)", level: .info)
        }
    }
    
    private func cleanupProfileTrash(_ profile: BackupProfile) async {
        guard profile.shouldCleanupTrash() else {
            return
        }
        
        let itemsToDelete = profile.getTrashItemsToCleanup()
        guard !itemsToDelete.isEmpty else {
            return
        }
        
        let trashDir = profile.trashPath()
        var deletedCount = 0
        
        for itemName in itemsToDelete {
            let itemPath = "\(trashDir)/\(itemName)"
            
            do {
                try FileManager.default.removeItem(atPath: itemPath)
                deletedCount += 1
                logManager.log("🗑️ Emptied trash item: \(itemName)", level: .debug)
            } catch {
                logManager.log("❌ Failed to delete trash item \(itemName): \(error)", level: .error)
            }
        }
        
        if deletedCount > 0 {
            logManager.log("✅ Emptied \(deletedCount) old items from trash for \(profile.name)", level: .info)
        }
    }
    
    // MARK: - Manual Cleanup Methods
    
    func cleanupProfileTrashManually(_ profile: BackupProfile) async {
        logManager.log("🧹 Manual trash cleanup for \(profile.name)", level: .info)
        
        let trashPath = profile.trashPath()
        
        do {
            try FileManager.default.removeItem(atPath: trashPath)
            try FileManager.default.createDirectory(atPath: trashPath, withIntermediateDirectories: true, attributes: nil)
            logManager.log("✅ Trash completely emptied for \(profile.name)", level: .info)
        } catch {
            logManager.log("❌ Failed to empty trash: \(error)", level: .error)
        }
    }
}
