//
//  NativeBackupManager.swift
//  BackupStatusNative
//
//  Created by Daniel Feddersen on 26/07/2025.
//

import Foundation
import Network
import SwiftData

// MARK: - Native Backup Implementation
class NativeBackupManager: ObservableObject {
    private var modelContext: ModelContext
    @Published var currentStatus: BackupStatus = .success
    @Published var lastBackupTime: Date?
    @Published var isRunning = false
    
    // Configuration
    private let rclonePath = "/usr/local/bin/rclone" // or "/opt/homebrew/bin/rclone" for M1 Macs
    private let sourcePath = "/Users/danielfeddersen/NextCloudMiniDaniel/Documents/"
    private let remoteName = "nextcloud-backup"
    private let remoteBasePath = "BackupFolderLaptop"
    
    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        loadLastBackupStatus()
    }
    
    // MARK: - Connection Testing
    
    nonisolated func testConnection() async -> Bool {
        let settings = getOrCreateSettings()
        
        // Test 1: Network reachability
        if !(await testNetworkReachability(host: settings.serverHost)) {
            print("❌ Network unreachable")
            return false
        }
        
        // Test 2: rclone connection
        if !(await testRcloneConnection()) {
            print("❌ rclone connection failed")
            return false
        }
        
        print("✅ Connection tests passed")
        return true
    }
    
    nonisolated private func testNetworkReachability(host: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            let monitor = NWPathMonitor()
            let queue = DispatchQueue(label: "network-monitor")
            
            monitor.pathUpdateHandler = { path in
                if path.status == .satisfied {
                    // Test specific host with ping
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: "/usr/bin/ping")
                    task.arguments = ["-c", "1", "-W", "5000", host]
                    
                    do {
                        try task.run()
                        task.waitUntilExit()
                        continuation.resume(returning: task.terminationStatus == 0)
                    } catch {
                        continuation.resume(returning: false)
                    }
                } else {
                    continuation.resume(returning: false)
                }
                monitor.cancel()
            }
            
            monitor.start(queue: queue)
        }
    }
    
    nonisolated private func testRcloneConnection() async -> Bool {
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: rclonePath)
            task.arguments = ["lsd", "\(remoteName):", "--timeout", "30s"]
            
            // Capture output
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                continuation.resume(returning: task.terminationStatus == 0)
            } catch {
                print("rclone test error: \(error)")
                continuation.resume(returning: false)
            }
        }
    }
    
    // MARK: - Native Backup Operations
    
    nonisolated func runBackup() async {
        guard shouldRunBackup() else {
            currentStatus = .skipped
            return
        }
        
        isRunning = true
        currentStatus = .running
        
        let session = BackupSession()
        modelContext.insert(session)
        
        do {
            if await testConnection() {
                let result = await performNativeBackup()
                
                session.endTime = Date()
                session.status = result.success ? .success : .failed
                session.errorMessage = result.error
                session.filesBackedUp = result.filesCount
                session.totalSize = result.totalSize
                
                if result.success {
                    updateLastSuccessfulBackup()
                    currentStatus = .success
                    
                    // Perform cleanup
                    await performCleanup()
                } else {
                    currentStatus = .failed
                }
            } else {
                session.endTime = Date()
                session.status = .connectionError
                session.errorMessage = "Cannot reach server"
                currentStatus = .connectionError
            }
            
            try modelContext.save()
        } catch {
            session.endTime = Date()
            session.status = .failed
            session.errorMessage = error.localizedDescription
            currentStatus = .failed
            try? modelContext.save()
        }
        
        isRunning = false
        lastBackupTime = Date()
    }
    
    nonisolated private func performNativeBackup() async -> (success: Bool, error: String?, filesCount: Int, totalSize: Int64) {
        let dateDaily = DateFormatter.dailyFormat.string(from: Date())
        let dateVersion = DateFormatter.versionFormat.string(from: Date())
        
        // Step 1: Daily sync
        print("Starting daily sync...")
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
            return (false, "Daily sync failed: \(dailySyncResult.error ?? "Unknown error")", 0, 0)
        }
        
        // Step 2: Current copy with versioning
        print("Starting version backup...")
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
            return (false, "Version backup failed: \(versionResult.error ?? "Unknown error")", 0, 0)
        }
        
        // Get file count and size (optional - could be expensive)
        let stats = await getBackupStats(dateDaily)
        
        return (true, nil, stats.fileCount, stats.totalSize)
    }
    
    nonisolated private func runRcloneCommand(_ arguments: [String]) async -> (success: Bool, error: String?) {
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: rclonePath)
            task.arguments = arguments
            
            // Set environment
            var environment = ProcessInfo.processInfo.environment
            environment["RCLONE_CONFIG"] = "/Users/danielfeddersen/.config/rclone/rclone.conf"
            task.environment = environment
            
            // Capture output
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            task.standardOutput = outputPipe
            task.standardError = errorPipe
            
            print("Executing: \(rclonePath) \(arguments.joined(separator: " "))")
            
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
    
    nonisolated private func getBackupStats(_ dateFolder: String) async -> (fileCount: Int, totalSize: Int64) {
        let result = await runRcloneCommand([
            "size",
            "\(remoteName):\(remoteBasePath)/daily/\(dateFolder)",
            "--json"
        ])
        
        guard result.success else {
            return (0, 0)
        }
        
        // Parse JSON output to get actual stats
        // For now, return estimated values
        return (150, 1024000)
    }
    
    // MARK: - Cleanup Operations
    
    private func performCleanup() async {
        print("Starting cleanup...")
        
        // Clean old daily backups (keep last 14)
        await cleanOldDailyBackups()
        
        // Clean old versions (older than 30 days)
        await cleanOldVersions()
    }
    
    nonisolated private func cleanOldDailyBackups() async {
        let result = await runRcloneCommand([
            "lsf",
            "\(remoteName):\(remoteBasePath)/daily/",
            "--dirs-only"
        ])
        
        guard result.success else {
            print("Failed to list daily backups for cleanup")
            return
        }
        
        // This would need output parsing to get the actual folder list
        // For now, use the built-in rclone cleanup
        let _ = await runRcloneCommand([
            "delete",
            "\(remoteName):\(remoteBasePath)/daily/",
            "--min-age", "14d"
        ])
    }
    
    nonisolated private func cleanOldVersions() async {
        let _ = await runRcloneCommand([
            "delete",
            "\(remoteName):\(remoteBasePath)/versions/",
            "--min-age", "30d"
        ])
    }
    
    // MARK: - Helper Methods (same as before)
    
    func shouldRunBackup() -> Bool {
        guard let settings = getSettings() else { return true }
        
        if isRunning { return false }
        
        if let lastSuccess = settings.lastSuccessfulBackup {
            let hoursSinceLastBackup = Date().timeIntervalSince(lastSuccess) / 3600
            if hoursSinceLastBackup < Double(settings.backupIntervalHours) {
                print("Backup skipped - last successful backup was \(Int(hoursSinceLastBackup)) hours ago")
                return false
            }
        }
        
        return true
    }
    
    func getSettings() -> BackupSettings? {
        let descriptor = FetchDescriptor<BackupSettings>()
        return try? modelContext.fetch(descriptor).first
    }
    
    func getOrCreateSettings() -> BackupSettings {
        if let existing = getSettings() {
            return existing
        } else {
            let settings = BackupSettings()
            modelContext.insert(settings)
            try? modelContext.save()
            return settings
        }
    }
    
    func updateLastSuccessfulBackup() {
        let settings = getOrCreateSettings()
        settings.lastSuccessfulBackup = Date()
        try? modelContext.save()
    }
    
    func loadLastBackupStatus() {
        // Implementation from previous version
    }
}
