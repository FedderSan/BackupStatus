//
//  BackupManager+EnhancedInit.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 21/10/2025.
//

import Foundation

extension BackupManager {
    // MARK: - Enhanced Initialization
    
       
    func performInitialization() async {
        logManager.log("🚀 BackupManager initialization started", level: .info)
        
        do {
            // Step 1: Verify database connection
            try await verifyDatabaseConnection()
            
            // Step 2: Load last backup status
            await loadLastBackupStatus()
            
            // Step 3: Verify external tools
            await verifyExternalTools()
            
            // Step 4: Load settings and validate
            await loadAndValidateSettings()
            
            // Step 5: Clean old sessions automatically
            await cleanOldSessionsAutomatically()
            
            isInitialized = true
            logManager.log("✅ BackupManager initialization completed successfully", level: .info)
            
        } catch {
            logManager.log("❌ BackupManager initialization failed: \(error)", level: .error)
            // Continue with partial initialization
            isInitialized = true
        }
    }
    
    func verifyDatabaseConnection() async throws {
        logManager.log("📊 Verifying database connection...", level: .debug)
        
        do {
            // Test basic database operations
            let recentCount = await dataActor.getRecentSessions(limit: 5).count
            logManager.log("📊 Database connection OK - found \(recentCount) recent sessions", level: .debug)
            
            // Ensure settings exist
            let _ = await dataActor.getOrCreateSettings()
            logManager.log("📊 Settings table verified", level: .debug)
            
        } catch {
            logManager.log("❌ Database connection issue: \(error)", level: .error)
            throw error
        }
    }
    
    func loadLastBackupStatus() async {
        logManager.log("📋 Loading last backup status...", level: .debug)
        
        let recent = await dataActor.getRecentSessions(limit: 1)
        if let last = recent.first {
            currentStatus = last.status
            lastBackupTime = last.endTime ?? last.startTime
            logManager.updateBackupStatus(last.status)
            
            let timeAgo = lastBackupTime.map { Date().timeIntervalSince($0) / 3600 } ?? 0
            logManager.log("📋 Last backup: \(last.status.rawValue) (\(String(format: "%.1f", timeAgo)) hours ago)", level: .info)
        } else {
            logManager.log("📋 No previous backups found", level: .info)
        }
    }
    
    func verifyExternalTools() async {
        logManager.log("🔧 Verifying external tools...", level: .debug)
        
        // Check rclone
        let rcloneExists = FileManager.default.fileExists(atPath: rclonePath)
        if rcloneExists {
            logManager.log("✅ rclone found at: \(rclonePath)", level: .debug)
        } else {
            logManager.log("⚠️ rclone not found at: \(rclonePath)", level: .warning)
        }
        
        // Check rsync (NEW: Check for real GNU rsync)
        if let realRsyncPath = self.realRsyncPath {
            logManager.log("✅ Real GNU rsync found at: \(realRsyncPath)", level: .debug)
                
            // Get and log version
            if let version = self.getRsyncVersion() {
                logManager.log("📦 rsync version: \(version)", level: .debug)
            }
        } else {
            logManager.log("⚠️ Real GNU rsync not found", level: .warning)
            logManager.log("💡 Install with: brew install rsync", level: .warning)
            logManager.log("ℹ️ macOS includes openrsync which is not fully compatible", level: .info)
            
            // Check if openrsync exists at standard location
            let openRsyncPath = "/usr/bin/rsync"
            if FileManager.default.fileExists(atPath: openRsyncPath) {
                logManager.log("ℹ️ Found macOS openrsync at \(openRsyncPath) (not compatible)", level: .info)
            }
        }
        
        // Check curl
        let curlPath = "/usr/bin/curl"
        let curlExists = FileManager.default.fileExists(atPath: curlPath)
        if curlExists {
            logManager.log("✅ curl found at: \(curlPath)", level: .debug)
        } else {
            logManager.log("⚠️ curl not found at: \(curlPath)", level: .warning)
        }
    }
    
    func loadAndValidateSettings() async {
        logManager.log("⚙️ Loading and validating settings...", level: .debug)
        
        let settings = await dataActor.getOrCreateSettings()
        let validation = settings.validateConfiguration()
        
        if validation.isValid {
            logManager.log("✅ Settings configuration is valid", level: .debug)
            logManager.log("📁 Source: \(settings.fullSourcePath)", level: .debug)
            logManager.log("🎯 Remote: \(settings.remoteType.displayName)", level: .debug)
            logManager.log("🗓️ Log retention: \(settings.logRetentionPeriod.displayName)", level: .debug)
        } else {
            logManager.log("⚠️ Settings configuration issues found:", level: .warning)
            for error in validation.errors {
                logManager.log("  - \(error)", level: .warning)
            }
        }
    }
    
    func cleanOldSessionsAutomatically() async {
        logManager.log("🧹 Running automatic session cleanup...", level: .debug)
        
        let totalBefore = await dataActor.getTotalSessionCount()
        logManager.log("📊 Total sessions before cleanup: \(totalBefore)", level: .debug)
        
        // Clean sessions older than 90 days (default retention period)
        await dataActor.cleanOldSessions(retentionDays: 90)
        
        let totalAfter = await dataActor.getTotalSessionCount()
        let cleaned = totalBefore - totalAfter
        
        if cleaned > 0 {
            logManager.log("🧹 Automatically cleaned \(cleaned) old session(s)", level: .info)
        } else {
            logManager.log("✅ No old sessions to clean", level: .debug)
        }
    }
}
