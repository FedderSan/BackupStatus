// MARK: - MenuBarView with Profile-Based Backups
import SwiftUI
import SwiftData

@MainActor
struct MenuBarView: View {
    @StateObject private var backupManager: BackupManager
    @ObservedObject var logManager: LogManager
    @State private var timer: Timer?
    @State private var showingForceBackupConfirmation = false
    @State private var showingConfigurationAlert = false
    @State private var configurationErrors: [String] = []
    @Environment(\.openWindow) private var openWindow
    
    // Debug Mode
    @AppStorage("debugModeEnabled") private var debugModeEnabled = false
    
    init(modelContainer: ModelContainer, logManager: LogManager) {
        self._backupManager = StateObject(wrappedValue: BackupManager(modelContainer: modelContainer, logManager: logManager))
        self.logManager = logManager
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Initialization Status
            if !backupManager.isInitialized {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Initializing...")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    Text("Loading backup system...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Divider()
            }
            
            // Debug Mode Indicator (when enabled)
            #if DEBUG
            Text("🔧 DEV BUILD ACTIVE")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.purple)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.purple.opacity(0.2))
                .cornerRadius(6)
            
            Divider()
            #else
            if debugModeEnabled {
                Text("🔧 DEBUG MODE ACTIVE")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.orange)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.orange.opacity(0.2))
                    .cornerRadius(6)
                
                Divider()
            }
            #endif
            
            // Backup Status Section
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: backupStatusIcon)
                        .foregroundColor(backupStatusColor)
                    Text("Backup: \(backupManager.currentStatus.rawValue.capitalized)")
                        .font(.headline)
                }
                
                if let lastBackup = backupManager.lastBackupTime {
                    Text("Last: \(lastBackup.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if backupManager.isRunning {
                    HStack {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Backup in progress...")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
            
            // Connection Status Section
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Image(systemName: backupManager.connectionStatus.systemImage)
                        .foregroundColor(backupManager.connectionStatus.color)
                    Text("Connection: \(backupManager.connectionStatus.displayName)")
                        .font(.headline)
                }
                
                if let lastConnectionTest = backupManager.lastConnectionTestTime {
                    Text("Last Test: \(lastConnectionTest.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Divider()
            
            // Profile-Based Backup Actions
            VStack(alignment: .leading, spacing: 4) {
                Button(action: {
                    runScheduledBackupSafely()
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Run Scheduled Backup")
                    }
                }
                .disabled(backupManager.isRunning || !backupManager.isInitialized)
                .help("Runs all enabled profiles, respecting their backup intervals")
                
                Button(action: {
                    runForceBackupSafely()
                }) {
                    HStack {
                        Image(systemName: "bolt.fill")
                        Text("Force Backup Now")
                    }
                }
                .disabled(backupManager.isRunning || !backupManager.isInitialized)
                .help("Immediately runs all enabled profiles, ignoring schedule")
            }
            
            Divider()
            
            Button("Test Connection") {
                Task { @MainActor [weak backupManager] in
                    guard let backupManager = backupManager else { return }
                    await backupManager.runConnectionTest()
                }
            }
            .disabled(backupManager.connectionStatus == .testing || !backupManager.isInitialized)
            
            Divider()
            
            // Window Actions
            Button("View History") {
                safeOpenWindow("history")
            }
            
            Button("View Log") {
                safeOpenWindow("log")
            }
            
            Button("Manage Profiles") {
                safeOpenWindow("profiles")
            }
            
            Button("Settings") {
                safeOpenWindow("settings")
            }
            
            // Debug Tools (shown when debug mode is enabled OR in DEBUG build)
            #if DEBUG
            debugMenuSection
            #else
            if debugModeEnabled {
                debugMenuSection
            }
            #endif
            
            Divider()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(minWidth: 220)
        .alert("Configuration Required", isPresented: $showingConfigurationAlert) {
            Button("Open Profiles") {
                logManager.log("🔧 User opened profiles from config alert", level: .info)
                safeOpenWindow("profiles")
            }
            Button("Cancel", role: .cancel) {
                logManager.log("❌ User cancelled configuration alert", level: .info)
            }
        } message: {
            if configurationErrors.isEmpty {
                Text("No enabled backup profiles found. Please create and enable at least one profile.")
            } else {
                Text("Profile configuration issues:\n\n" + configurationErrors.joined(separator: "\n"))
            }
        }
        .alert("Force Backup", isPresented: $showingForceBackupConfirmation) {
            Button("Cancel", role: .cancel) {
                logManager.log("❌ User cancelled force backup confirmation", level: .info)
            }
            Button("Run Backup", role: .destructive) {
                logManager.log("✅ User confirmed force backup", level: .info)
                Task { @MainActor [weak backupManager] in
                    guard let backupManager = backupManager else { return }
                    await backupManager.runAllProfileBackups(force: true)
                }
            }
        } message: {
            if let lastBackup = backupManager.lastBackupTime {
                let minutesAgo = Int(Date().timeIntervalSince(lastBackup) / 60)
                if minutesAgo < 60 {
                    Text("Last backup was \(minutesAgo) minute\(minutesAgo == 1 ? "" : "s") ago. Are you sure you want to run another backup now?")
                } else {
                    let hoursAgo = minutesAgo / 60
                    Text("Last backup was \(hoursAgo) hour\(hoursAgo == 1 ? "" : "s") ago. Are you sure you want to run another backup now?")
                }
            } else {
                Text("Are you sure you want to run a backup now?")
            }
        }
        .onAppear {
            startPeriodicBackup()
            
            // Run startup diagnostics
            Task { @MainActor [weak backupManager] in
                guard let backupManager = backupManager else { return }
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                await backupManager.runStartupDiagnostics()
            }
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
    // MARK: - Debug Menu Section
    
    private var debugMenuSection: some View {
        Group {
            Divider()
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Debug Tools")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Button("🔍 Debug Connection") {
                    Task { @MainActor [weak backupManager] in
                        guard let backupManager = backupManager else { return }
                        await backupManager.debugConnection()
                    }
                }
                .disabled(!backupManager.isInitialized)
                
                Button("🔧 Debug rclone Config") {
                    Task { @MainActor [weak backupManager] in
                        guard let backupManager = backupManager else { return }
                        await backupManager.debugRcloneConfig()
                    }
                }
                .disabled(!backupManager.isInitialized)
                
                Button("🔐 Debug Password") {
                    Task { @MainActor [weak backupManager] in
                        guard let backupManager = backupManager else { return }
                        await backupManager.debugPasswordHandling()
                    }
                }
                .disabled(!backupManager.isInitialized)
                
                Button("📊 Run Diagnostics") {
                    Task { @MainActor [weak backupManager] in
                        guard let backupManager = backupManager else { return }
                        await backupManager.runStartupDiagnostics()
                    }
                }
                .disabled(!backupManager.isInitialized)
                
                Divider()
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("Log Management")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    
                    Button("🧹 Clean Old Logs") {
                        Task { @MainActor [weak logManager] in
                            guard let logManager = logManager else { return }
                            await logManager.forceCleanOldLogs()
                        }
                    }
                }
                
                Button("Debug Tools") {
                    safeOpenWindow("debug")
                }
            }
            
            // Exit Debug Mode button (only shown in Release builds when debug mode is enabled)
            #if !DEBUG
            if debugModeEnabled {
                Divider()
                
                Button(action: {
                    debugModeEnabled = false
                    logManager.log("❌ Debug mode disabled", level: .info)
                }) {
                    Label("Exit Debug Mode", systemImage: "xmark.circle.fill")
                        .foregroundColor(.red)
                }
            }
            #endif
        }
    }
    
    // MARK: - Safe Action Methods
    
    private func runScheduledBackupSafely() {
        logManager.log("🔄 Scheduled backup button clicked", level: .info)
        
        guard backupManager.isInitialized else {
            logManager.log("❌ BackupManager not yet initialized", level: .error)
            return
        }
        
        Task { @MainActor in
            // Get all enabled profiles and validate them
            let profiles = await backupManager.getEnabledProfiles()
            
            guard !profiles.isEmpty else {
                logManager.log("❌ No enabled profiles found", level: .error)
                configurationErrors = []
                showingConfigurationAlert = true
                return
            }
            
            logManager.log("📋 Found \(profiles.count) enabled profile(s)", level: .info)
            
            // Validate all enabled profiles
            var hasInvalidProfiles = false
            var allErrors: [String] = []
            
            for profile in profiles {
                let validation = profile.validateConfiguration()
                if !validation.isValid {
                    hasInvalidProfiles = true
                    allErrors.append("\(profile.name): " + validation.errors.joined(separator: ", "))
                    logManager.log("❌ Profile '\(profile.name)' has configuration errors: \(validation.errors.joined(separator: ", "))", level: .error)
                }
            }
            
            if hasInvalidProfiles {
                configurationErrors = allErrors
                showingConfigurationAlert = true
                return
            }
            
            logManager.log("✅ All profiles valid", level: .info)
            
            // Check if any backups are recent
            let hasRecentBackup = profiles.contains { profile in
                if let lastBackup = profile.lastSuccessfulBackup {
                    let hoursSince = Date().timeIntervalSince(lastBackup) / 3600
                    return hoursSince < 1
                }
                return false
            }
            
            if hasRecentBackup {
                logManager.log("⚠️ Recent backup detected, showing confirmation", level: .info)
                showingForceBackupConfirmation = true
            } else {
                logManager.log("🚀 Running scheduled backup", level: .info)
                await backupManager.runAllProfileBackups(force: false)
            }
        }
    }
    
    private func runForceBackupSafely() {
        logManager.log("🔥 Force backup button clicked", level: .info)
        
        guard backupManager.isInitialized else {
            logManager.log("❌ BackupManager not yet initialized", level: .error)
            return
        }
        
        Task { @MainActor in
            // Get all enabled profiles and validate them
            let profiles = await backupManager.getEnabledProfiles()
            
            guard !profiles.isEmpty else {
                logManager.log("❌ No enabled profiles found", level: .error)
                configurationErrors = []
                showingConfigurationAlert = true
                return
            }
            
            logManager.log("📋 Found \(profiles.count) enabled profile(s) for force backup", level: .info)
            
            // Validate all enabled profiles
            var hasInvalidProfiles = false
            var allErrors: [String] = []
            
            for profile in profiles {
                let validation = profile.validateConfiguration()
                if !validation.isValid {
                    hasInvalidProfiles = true
                    allErrors.append("\(profile.name): " + validation.errors.joined(separator: ", "))
                    logManager.log("❌ Profile '\(profile.name)' has configuration errors: \(validation.errors.joined(separator: ", "))", level: .error)
                }
            }
            
            if hasInvalidProfiles {
                configurationErrors = allErrors
                showingConfigurationAlert = true
                return
            }
            
            logManager.log("🚀 Force backup - running immediately (no restrictions)", level: .info)
            await backupManager.runAllProfileBackups(force: true)
        }
    }
    
    private func safeOpenWindow(_ identifier: String) {
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 10_000_000)
            self.openWindow(id: identifier)
        }
    }
    
    // MARK: - UI Helpers
    
    private var backupStatusIcon: String {
        switch backupManager.currentStatus {
        case .success:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        case .running:
            return "arrow.clockwise.circle"
        case .connectionError:
            return "wifi.exclamationmark"
        case .skipped:
            return "forward.circle"
        }
    }
    
    private var backupStatusColor: Color {
        switch backupManager.currentStatus {
        case .success:
            return .green
        case .failed, .connectionError:
            return .red
        case .running:
            return .blue
        case .skipped:
            return .orange
        }
    }
    
    private func startPeriodicBackup() {
        timer?.invalidate()
        
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { [weak backupManager, weak logManager] _ in
            guard let backupManager = backupManager, let logManager = logManager else { return }
            
            Task { @MainActor in
                guard !backupManager.isRunning && backupManager.isInitialized else { return }
                logManager.log("⏰ Periodic backup timer triggered", level: .debug)
                await backupManager.runAllProfileBackups(force: false)
            }
        }
        
        logManager.log("⏰ Periodic backup timer created (5-minute interval)", level: .debug)
    }
}
