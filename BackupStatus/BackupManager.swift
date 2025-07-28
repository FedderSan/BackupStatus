// MARK: - Main Backup Manager (UI Thread)
import Foundation
//import SwiftUI
import SwiftData

@MainActor
class BackupManager: ObservableObject {
    @Published var currentStatus: BackupStatus = .success
    @Published var lastBackupTime: Date?
    @Published var isRunning = false
    
    private let dataActor: BackupDataActor
    
    // Configuration
    private let rclonePath = "/usr/local/bin/rclone"
    //private let rclonePath = "/opt/homebrew/bin/rclone"
    private let sourcePath = "/Users/danielfeddersen/NextCloudMiniDaniel/Documents/"
    private let remoteName = "nextcloud-backup"
    private let remoteBasePath = "BackupFolderLaptop"
    
    init(modelContainer: ModelContainer) {
        self.dataActor = BackupDataActor(modelContainer: modelContainer)
        Task {
            await loadLastBackupStatus()
        }
    }
    
    func runBackup() async {
        guard await shouldRunBackup() else {
            currentStatus = .skipped
            return
        }
        
        isRunning = true
        currentStatus = .running
        
        do {
            // Create session in database actor
            let session = await dataActor.createBackupSession()
            let sessionID = session.persistentModelID
            
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
                } else {
                    currentStatus = .failed
                }
            }
            
        } catch {
            print("Database error: \(error)")
            currentStatus = .failed
        }
        
        isRunning = false
        lastBackupTime = Date()
    }
    
    // MARK: - Background Work (No Database Access)
    
    private func performBackupWork() async -> (success: Bool, error: String?, filesCount: Int, totalSize: Int64) {
        // Test connection
        if !(await testConnection()) {
            return (false, "Connection failed", 0, 0)
        }
        
        // Do backup
        return await performNativeBackup()
    }
    
    func testConnection() async -> Bool {
        // Get settings from database
        guard let settings = await dataActor.getSettings() else {
            print("❌ No settings found in database")
            return false
        }
        
        // Test 1: Network reachability using database settings
        if !(await testNetworkReachability(host: settings.serverHost)) {
            print("❌ Network unreachable to \(settings.serverHost)")
            return false
        }
        
        // Test 2: rclone connection
        if !(await testRcloneConnection()) {
            print("❌ rclone connection failed")
            return false
        }
        
        print("✅ Connection tests passed for \(settings.serverHost):\(settings.serverPort)")
        return true
    }
    
    private func testNetworkReachability(host: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/sbin/ping")
            task.arguments = ["-c", "1", "-W", "5000", host]
            
            do {
                try task.run()
                task.waitUntilExit()
                continuation.resume(returning: task.terminationStatus == 0)
            } catch {
                print("Failed to run ping to \(host): \(error)")
                continuation.resume(returning: false)
            }
        }
    }
    
    private func testRcloneConnection() async -> Bool {
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
                continuation.resume(returning: task.terminationStatus == 0)
            } catch {
                print("rclone test error: \(error)")
                continuation.resume(returning: false)
            }
        }
    }
    
    private func performNativeBackup() async -> (success: Bool, error: String?, filesCount: Int, totalSize: Int64) {
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
        
        // Get file count and size
        let stats = await getBackupStats(dateDaily)
        
        return (true, nil, stats.fileCount, stats.totalSize)
    }
    
    private func runRcloneCommand(_ arguments: [String]) async -> (success: Bool, error: String?) {
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
    
    private func getBackupStats(_ dateFolder: String) async -> (fileCount: Int, totalSize: Int64) {
        let result = await runRcloneCommand([
            "size",
            "\(remoteName):\(remoteBasePath)/daily/\(dateFolder)",
            "--json"
        ])
        
        guard result.success else {
            return (0, 0)
        }
        
        return (150, 1024000)
    }
    
    private func performCleanupWork() async {
        print("Starting cleanup...")
        
        let _ = await runRcloneCommand([
            "delete",
            "\(remoteName):\(remoteBasePath)/daily/",
            "--min-age", "14d"
        ])
        
        let _ = await runRcloneCommand([
            "delete",
            "\(remoteName):\(remoteBasePath)/versions/",
            "--min-age", "30d"
        ])
    }
    
    // MARK: - Database Helper Methods (Using Actor)
    
    private func shouldRunBackup() async -> Bool {
        guard let settings = await dataActor.getSettings() else { return true }
        
        if isRunning { return false }
        
        if let lastSuccess = settings.lastSuccessfulBackup {
            let hoursSinceLastBackup = Date().timeIntervalSince(lastSuccess) / 3600
            //test switched <>
            if hoursSinceLastBackup > Double(settings.backupIntervalHours) {
                print("Backup skipped - last successful backup was \(Int(hoursSinceLastBackup)) hours ago")
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
            lastBackupTime = last.endTime ?? last.startTime
        }
    }
    
    func cleanOldSessions() async {
        await dataActor.cleanOldSessions()
    }
    
    // MARK: - Settings Access Methods
    
    func getSettings() async -> BackupSettings? {
        return await dataActor.getSettings()
    }
    
    func getOrCreateSettings() async -> BackupSettings {
        return await dataActor.getOrCreateSettings()
    }
}
