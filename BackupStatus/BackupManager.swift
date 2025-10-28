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
    
    // MARK: - Connection Testing (Profile-Based)
    
    func runConnectionTest() async {
        logManager.log("🔍 Starting connection test for all enabled profiles", level: .info)
        updateConnectionStatus(.testing)
        
        // Get all enabled profiles
        let profiles = await getEnabledProfiles()
        
        guard !profiles.isEmpty else {
            updateConnectionStatus(.failed)
            logManager.log("❌ No enabled profiles to test", level: .error)
            return
        }
        
        logManager.log("📋 Testing \(profiles.count) enabled profile(s)", level: .info)
        
        // Test connection for all enabled profiles
        let isConnected = await testConnection()
        
        updateConnectionStatus(isConnected ? .connected : .failed)
        logManager.log("Connection test result: \(isConnected ? "✅ SUCCESS" : "❌ FAILED")", level: isConnected ? .info : .error)
    }
    
    // MARK: - Hard Link Copy (Used by Profile Backups)
    
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
