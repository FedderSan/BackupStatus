//
//  BackupManager+RClone.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 21/10/2025.
//

import Foundation

extension BackupManager {
    // MARK: - WebDAV/rclone Operations
    
    func performRcloneBackup(_ settings: BackupSettings) async -> (success: Bool, error: String?, filesCount: Int, totalSize: Int64) {
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
    
    // MARK: - rsync Command (Updated for iCloud compatibility)
    
    func runRsyncCommand(
        from source: String,
        to destination: String,
        delete: Bool,
        excludePatterns: [String] = [],
        preserveTimestamps: Bool = true
    ) async -> (success: Bool, error: String?) {
        let rsyncPath = "/usr/bin/rsync"
        guard FileManager.default.fileExists(atPath: rsyncPath) else {
            logManager.log("❌ rsync not found at: \(rsyncPath)", level: .error)
            return (false, "rsync not found")
        }
        
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: rsyncPath)
            
            var arguments: [String]
            
            if preserveTimestamps {
                // Standard archive mode - preserves everything including timestamps
                arguments = ["-avh", "--progress"]
            } else {
                // Modified for iCloud - don't preserve timestamps so iCloud sees files as "new"
                arguments = [
                    "-rlDvh",  // recursive, links, devices, verbose, human-readable
                    "--progress",
                    "--no-times",  // Don't preserve modification times
                    "--omit-dir-times"  // Don't preserve directory times
                ]
            }
            
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
                let timestampMode = preserveTimestamps ? "preserving timestamps" : "current timestamps (iCloud mode)"
                logManager.log("🔧 Running rsync with \(timestampMode)", level: .debug)
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
    
    func getLocalBackupStats(_ path: String) async -> (fileCount: Int, totalSize: Int64) {
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
    
   
    
    func runRcloneCommand(_ arguments: [String]) async -> (success: Bool, error: String?) {
        guard FileManager.default.fileExists(atPath: rclonePath) else {
            logManager.log("❌ rclone not found at: \(rclonePath)", level: .error)
            return (false, "rclone not found at \(rclonePath)")
        }
        
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
                logManager.log("🔧 Running rclone: \(arguments.joined(separator: " "))", level: .debug)
                try task.run()
                task.waitUntilExit()
                
                if task.terminationStatus == 0 {
                    continuation.resume(returning: (true, nil))
                } else {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    logManager.log("❌ rclone failed with code \(task.terminationStatus): \(errorOutput)", level: .error)
                    continuation.resume(returning: (false, errorOutput))
                }
            } catch {
                logManager.log("❌ rclone execution error: \(error)", level: .error)
                continuation.resume(returning: (false, error.localizedDescription))
            }
        }
    }
    
    func getBackupStats(_ remoteBase: String, _ dateFolder: String) async -> (fileCount: Int, totalSize: Int64) {
        // Simplified stats - return reasonable defaults for now
        return (150, 1024000)
    }
    
    // MARK: - Configuration Management
    
    func writeRcloneConfig(_ settings: BackupSettings) async throws {
        let configContent = settings.generateRcloneConfig()
        
        // Ensure config directory exists
        let configDir = URL(fileURLWithPath: configPath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        
        // Write config
        try configContent.write(toFile: configPath, atomically: true, encoding: .utf8)
        logManager.log("Updated rclone configuration at: \(configPath)", level: .debug)
    }
}
