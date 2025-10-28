//
//  BackupManager+Profiles.swift
//  BackupStatus
//
//  Multi-profile backup support with WebDAV and Local - WITH SESSION TRACKING
//

import Foundation
import SwiftData

extension BackupManager {
    
    // MARK: - Profile Management
    
    func getAllProfiles() async -> [BackupProfile] {
        return await dataActor.getAllProfiles()
    }
    
    func getEnabledProfiles() async -> [BackupProfile] {
        return await dataActor.getEnabledProfiles()
    }
    
    func createProfile(name: String, type: BackupProfileType, remoteType: ProfileRemoteType = .local) async -> BackupProfile {
        let profile = await dataActor.createProfile(name: name, type: type)
        profile.remoteType = remoteType
        logManager.log("✅ Created new profile: \(name) (\(type.displayName), \(remoteType.displayName))", level: .info)
        return profile
    }
    
    func deleteProfile(_ profile: BackupProfile) async {
        await dataActor.deleteProfile(profile)
        logManager.log("🗑️ Deleted profile: \(profile.name)", level: .info)
    }
    
    func updateProfileStats(_ profileID: PersistentIdentifier, filesCount: Int, totalSize: Int64) async {
        do {
            try await dataActor.updateProfileStats(profileID, filesCount: filesCount, totalSize: totalSize)
        } catch {
            logManager.log("❌ Failed to update profile stats: \(error)", level: .error)
        }
    }
    
    // MARK: - Run All Profiles
    
    func runAllProfileBackups(force: Bool = false) async {
        logManager.log("🚀 Running all enabled profile backups (force: \(force))", level: .info)
        
        let profiles = await getEnabledProfiles()
        
        guard !profiles.isEmpty else {
            logManager.log("⚠️ No enabled profiles found", level: .warning)
            return
        }
        
        logManager.log("📋 Found \(profiles.count) enabled profile(s)", level: .info)
        
        for profile in profiles {
            logManager.log("▶️ Running profile: \(profile.name) (\(profile.remoteType.displayName))", level: .info)
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
        
        // Get profile ID for updates
        let profileID = profile.persistentModelID
        
        logManager.log("🔄 Starting backup for profile: \(profile.name)", level: .info)
        logManager.log("📁 Source: \(profile.fullSourcePath)", level: .debug)
        logManager.log("🎯 Destination: \(profile.fullDestinationPath)", level: .debug)
        logManager.log("🔧 Type: \(profile.profileType.displayName)", level: .debug)
        logManager.log("🌐 Remote: \(profile.remoteType.displayName)", level: .debug)
        
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
        
        // Set up rclone config for WebDAV profiles
        if profile.remoteType == .webdav {
            do {
                try await writeProfileRcloneConfig(profile)
            } catch {
                logManager.log("❌ Failed to write rclone config: \(error)", level: .error)
                return
            }
        }
        
        // Run backup based on profile type and remote type
        switch (profile.profileType, profile.remoteType) {
        case (.versioned, .local):
            await runVersionedLocalBackup(profile, profileID: profileID)
        case (.versioned, .webdav):
            await runVersionedWebDAVBackup(profile, profileID: profileID)
        case (.oneWaySync, .local):
            await runOneWaySyncLocalBackup(profile, profileID: profileID)
        case (.oneWaySync, .webdav):
            await runOneWaySyncWebDAVBackup(profile, profileID: profileID)
        }
    }
    
    // MARK: - Local Versioned Backup
    
    private func runVersionedLocalBackup(_ profile: BackupProfile, profileID: PersistentIdentifier) async {
        logManager.log("📦 Running local versioned backup for: \(profile.name)", level: .info)
        
        // Create backup session and get its ID
        let sessionID = await dataActor.createBackupSession()
        
        guard hasRealRsync else {
            logManager.log("❌ Cannot run versioned backup: Real GNU rsync required", level: .error)
            logManager.log("💡 Install with: brew install rsync", level: .error)
            
            // Mark session as failed
            do {
                try await dataActor.updateSessionStatus(sessionID, status: .failed, error: "Real GNU rsync not found")
            } catch {
                logManager.log("❌ Failed to update session status: \(error)", level: .error)
            }
            return
        }
        
        let fileManager = FileManager.default
        let date = Date()
        
        do {
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
                do {
                    try await dataActor.updateSessionStatus(sessionID, status: .failed, error: latestResult.error)
                } catch {
                    logManager.log("❌ Failed to update session status: \(error)", level: .error)
                }
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
                
                let linkResult = await runHardLinkCopy(from: latestPath, to: versionPath)
                
                if !linkResult.success {
                    logManager.log("⚠️ Hard link failed, using regular copy", level: .warning)
                    
                    let sourceWithSlash = latestPath.hasSuffix("/") ? latestPath : "\(latestPath)/"
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
                
                await cleanupProfileVersions(profile)
            }
            
            let stats = await getLocalBackupStats(latestPath)
            await updateProfileStats(profileID, filesCount: stats.fileCount, totalSize: stats.totalSize)
            
            // Mark session as successful
            do {
                try await dataActor.updateSession(
                    sessionID,
                    success: true,
                    error: nil,
                    filesCount: stats.fileCount,
                    totalSize: stats.totalSize
                )
            } catch {
                logManager.log("❌ Failed to update session: \(error)", level: .error)
            }
            
            logManager.log("✅ Versioned backup completed for \(profile.name): \(stats.fileCount) files, \(ByteCountFormatter.string(fromByteCount: stats.totalSize, countStyle: .file))", level: .info)
            
        } catch {
            logManager.log("❌ Versioned backup failed for \(profile.name): \(error)", level: .error)
            do {
                try await dataActor.updateSessionStatus(sessionID, status: .failed, error: error.localizedDescription)
            } catch {
                logManager.log("❌ Failed to update session status: \(error)", level: .error)
            }
        }
    }
    
    // MARK: - WebDAV Versioned Backup
    
    private func runVersionedWebDAVBackup(_ profile: BackupProfile, profileID: PersistentIdentifier) async {
        logManager.log("☁️ Running WebDAV versioned backup for: \(profile.name)", level: .info)
        
        // Create backup session and get its ID
        let sessionID = await dataActor.createBackupSession()
        
        let dateVersion = DateFormatter.versionFormat.string(from: Date())
        let remoteBase = profile.fullDestinationPath
        
        var excludeArgs: [String] = []
        for pattern in profile.excludeArray {
            excludeArgs.append("--exclude")
            excludeArgs.append(pattern)
        }
        
        // Step 1: Sync to 'latest' folder
        logManager.log("Syncing to latest folder on WebDAV", level: .info)
        var latestArgs = [
            "sync",
            profile.fullSourcePath,
            "\(remoteBase)/latest",
            "--progress",
            "--transfers", "4",
            "--timeout", "300s"
        ]
        latestArgs.append(contentsOf: excludeArgs)
        
        let latestResult = await runRcloneCommand(latestArgs)
        
        guard latestResult.success else {
            logManager.log("❌ Latest sync failed: \(latestResult.error ?? "Unknown")", level: .error)
            do {
                try await dataActor.updateSessionStatus(sessionID, status: .failed, error: latestResult.error)
            } catch {
                logManager.log("❌ Failed to update session status: \(error)", level: .error)
            }
            return
        }
        
        // Step 2: Create version if enabled
        if profile.createVersions {
            logManager.log("Creating version backup: \(dateVersion)", level: .info)
            
            // Try server-side copy first (much faster)
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
                
                var directArgs = [
                    "copy",
                    profile.fullSourcePath,
                    "\(remoteBase)/versions/\(dateVersion)",
                    "--progress",
                    "--transfers", "4",
                    "--timeout", "300s"
                ]
                directArgs.append(contentsOf: excludeArgs)
                
                let directResult = await runRcloneCommand(directArgs)
                if !directResult.success {
                    logManager.log("❌ Version backup failed: \(directResult.error ?? "Unknown")", level: .warning)
                }
            }
        }
        
        // Get stats (estimated for WebDAV - TODO: implement proper rclone stats)
        let stats = (fileCount: 100, totalSize: Int64(1024000))
        await updateProfileStats(profileID, filesCount: stats.fileCount, totalSize: stats.totalSize)
        
        // Mark session as successful
        do {
            try await dataActor.updateSession(
                sessionID,
                success: true,
                error: nil,
                filesCount: stats.fileCount,
                totalSize: stats.totalSize
            )
        } catch {
            logManager.log("❌ Failed to update session: \(error)", level: .error)
        }
        
        logManager.log("✅ WebDAV backup completed for \(profile.name)", level: .info)
    }
    
    // MARK: - Local One-Way Sync
    
    private func runOneWaySyncLocalBackup(_ profile: BackupProfile, profileID: PersistentIdentifier) async {
        logManager.log("🔄 Running local one-way sync for: \(profile.name)", level: .info)
        
        // Create backup session and get its ID
        let sessionID = await dataActor.createBackupSession()
        
        guard hasRealRsync else {
            logManager.log("❌ Cannot run one-way sync: Real GNU rsync required", level: .error)
            logManager.log("💡 Install with: brew install rsync", level: .error)
            
            // Mark session as failed
            do {
                try await dataActor.updateSessionStatus(sessionID, status: .failed, error: "Real GNU rsync not found")
            } catch {
                logManager.log("❌ Failed to update session status: \(error)", level: .error)
            }
            return
        }
        
        let fileManager = FileManager.default
        let date = Date()
        
        do {
            var excludeArgs: [String] = []
            for pattern in profile.excludeArray {
                excludeArgs.append("--exclude")
                excludeArgs.append(pattern)
            }
            
            if profile.useTrashFolder {
                excludeArgs.append("--exclude")
                excludeArgs.append(profile.trashFolderName)
            }
            
            let destinationPath = profile.fullDestinationPath
            try fileManager.createDirectory(atPath: destinationPath, withIntermediateDirectories: true, attributes: nil)
            
            if profile.useTrashFolder {
                let trashPath = profile.trashPath()
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
                let trashTimestamp = dateFormatter.string(from: date)
                let trashSessionPath = "\(trashPath)/\(trashTimestamp)"
                
                try fileManager.createDirectory(atPath: trashSessionPath, withIntermediateDirectories: true, attributes: nil)
                logManager.log("🗑️ Created trash folder: \(trashSessionPath)", level: .info)
                
                let syncResult = await runRsyncWithTrash(
                    from: profile.fullSourcePath,
                    to: destinationPath,
                    trashDir: trashSessionPath,
                    excludePatterns: excludeArgs
                )
                
                guard syncResult.success else {
                    logManager.log("❌ One-way sync failed: \(syncResult.error ?? "Unknown")", level: .error)
                    do {
                        try await dataActor.updateSessionStatus(sessionID, status: .failed, error: syncResult.error)
                    } catch {
                        logManager.log("❌ Failed to update session status: \(error)", level: .error)
                    }
                    return
                }
                
                if let trashContents = try? fileManager.contentsOfDirectory(atPath: trashSessionPath) {
                    if trashContents.isEmpty {
                        try? fileManager.removeItem(atPath: trashSessionPath)
                        logManager.log("✅ No files deleted - removed empty trash folder", level: .debug)
                    } else {
                        logManager.log("🗑️ Moved \(trashContents.count) items to trash", level: .info)
                    }
                }
                
                if profile.shouldCleanupTrash() {
                    await cleanupProfileTrash(profile)
                }
                
            } else {
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
                    do {
                        try await dataActor.updateSessionStatus(sessionID, status: .failed, error: syncResult.error)
                    } catch {
                        logManager.log("❌ Failed to update session status: \(error)", level: .error)
                    }
                    return
                }
            }
            
            let stats = await getLocalBackupStats(destinationPath)
            await updateProfileStats(profileID, filesCount: stats.fileCount, totalSize: stats.totalSize)
            
            // Mark session as successful
            do {
                try await dataActor.updateSession(
                    sessionID,
                    success: true,
                    error: nil,
                    filesCount: stats.fileCount,
                    totalSize: stats.totalSize
                )
            } catch {
                logManager.log("❌ Failed to update session: \(error)", level: .error)
            }
            
            logManager.log("✅ One-way sync completed for \(profile.name): \(stats.fileCount) files, \(ByteCountFormatter.string(fromByteCount: stats.totalSize, countStyle: .file))", level: .info)
            
        } catch {
            logManager.log("❌ One-way sync failed for \(profile.name): \(error)", level: .error)
            do {
                try await dataActor.updateSessionStatus(sessionID, status: .failed, error: error.localizedDescription)
            } catch {
                logManager.log("❌ Failed to update session status: \(error)", level: .error)
            }
        }
    }
    
    // MARK: - WebDAV One-Way Sync
    
    private func runOneWaySyncWebDAVBackup(_ profile: BackupProfile, profileID: PersistentIdentifier) async {
        logManager.log("☁️ Running WebDAV one-way sync for: \(profile.name)", level: .info)
        
        // Create backup session and get its ID
        let sessionID = await dataActor.createBackupSession()
        
        let remoteBase = profile.fullDestinationPath
        
        var syncArgs = [
            "sync",
            profile.fullSourcePath,
            remoteBase,
            "--progress",
            "--transfers", "4",
            "--timeout", "300s"
        ]
        
        // Add exclude patterns
        for pattern in profile.excludeArray {
            syncArgs.append("--exclude")
            syncArgs.append(pattern)
        }
        
        if profile.useTrashFolder {
            logManager.log("⚠️ WebDAV trash folder not yet implemented, using hard delete", level: .warning)
        }
        
        let syncResult = await runRcloneCommand(syncArgs)
        
        guard syncResult.success else {
            logManager.log("❌ WebDAV sync failed: \(syncResult.error ?? "Unknown")", level: .error)
            do {
                try await dataActor.updateSessionStatus(sessionID, status: .failed, error: syncResult.error)
            } catch {
                logManager.log("❌ Failed to update session status: \(error)", level: .error)
            }
            return
        }
        
        // Get stats (estimated for WebDAV - TODO: implement proper rclone stats)
        let stats = (fileCount: 100, totalSize: Int64(1024000))
        await updateProfileStats(profileID, filesCount: stats.fileCount, totalSize: stats.totalSize)
        
        // Mark session as successful
        do {
            try await dataActor.updateSession(
                sessionID,
                success: true,
                error: nil,
                filesCount: stats.fileCount,
                totalSize: stats.totalSize
            )
        } catch {
            logManager.log("❌ Failed to update session: \(error)", level: .error)
        }
        
        logManager.log("✅ WebDAV sync completed for \(profile.name)", level: .info)
    }
    
    // MARK: - rsync with Trash Support (HELPER FUNCTION)
    
    private func runRsyncWithTrash(
        from source: String,
        to destination: String,
        trashDir: String,
        excludePatterns: [String] = []
    ) async -> (success: Bool, error: String?) {
        guard let rsyncPath = realRsyncPath else {
            return (false, "Real GNU rsync not found. Install with: brew install rsync")
        }
        
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: rsyncPath)
            
            // Ensure both source and destination have trailing slashes
            let sourceWithSlash = source.hasSuffix("/") ? source : "\(source)/"
            let destWithSlash = destination.hasSuffix("/") ? destination : "\(destination)/"
            
            var arguments = [
                "-avh",
                "--progress",
                "--delete",
                "--backup",
                "--backup-dir=\(trashDir)",
                "--suffix=",
            ]
            
            // Add exclude patterns
            arguments.append(contentsOf: excludePatterns)
            
            arguments.append(sourceWithSlash)
            arguments.append(destWithSlash)
            
            task.arguments = arguments
            
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            task.standardOutput = outputPipe
            task.standardError = errorPipe
            
            do {
                logManager.log("🔧 Running rsync with trash: \(trashDir)", level: .debug)
                logManager.log("📝 Command: rsync \(arguments.joined(separator: " "))", level: .debug)
                try task.run()
                task.waitUntilExit()
                
                let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let outputString = String(data: outputData, encoding: .utf8) ?? ""
                
                if task.terminationStatus == 0 {
                    if !outputString.isEmpty {
                        logManager.log("📊 rsync output:\n\(outputString)", level: .debug)
                    }
                    continuation.resume(returning: (true, nil))
                } else {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    logManager.log("❌ rsync failed with code \(task.terminationStatus)", level: .error)
                    logManager.log("❌ Error: \(errorOutput)", level: .error)
                    continuation.resume(returning: (false, errorOutput))
                }
            } catch {
                logManager.log("❌ rsync execution error: \(error)", level: .error)
                continuation.resume(returning: (false, error.localizedDescription))
            }
        }
    }
    
    // MARK: - Helper Methods
    
    private func writeProfileRcloneConfig(_ profile: BackupProfile) async throws {
        let configContent = profile.generateRcloneConfig()
        
        let configDir = URL(fileURLWithPath: configPath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        
        // Read existing config if it exists
        var fullConfigContent = ""
        
        if FileManager.default.fileExists(atPath: configPath) {
            let existingContent = try String(contentsOfFile: configPath, encoding: .utf8)
            fullConfigContent = updateExistingConfig(existingContent, with: configContent, remoteName: profile.webdavRemoteName)
        } else {
            fullConfigContent = configContent
        }
        
        try fullConfigContent.write(toFile: configPath, atomically: true, encoding: .utf8)
        logManager.log("Updated rclone configuration for profile: \(profile.name)", level: .debug)
    }
    
    private func updateExistingConfig(_ existingContent: String, with newConfig: String, remoteName: String) -> String {
        let lines = existingContent.components(separatedBy: .newlines)
        var updatedLines: [String] = []
        var skipUntilNextSection = false
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            if trimmedLine.hasPrefix("[") && trimmedLine.hasSuffix("]") {
                let sectionName = String(trimmedLine.dropFirst().dropLast())
                
                if sectionName == remoteName {
                    skipUntilNextSection = true
                    continue
                } else {
                    skipUntilNextSection = false
                }
            }
            
            if !skipUntilNextSection {
                updatedLines.append(line)
            }
        }
        
        if !updatedLines.isEmpty && !updatedLines.last!.isEmpty {
            updatedLines.append("")
        }
        updatedLines.append(newConfig)
        
        return updatedLines.joined(separator: "\n")
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
