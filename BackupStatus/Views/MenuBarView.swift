// MARK: - Updated MenuBarView with Force Backup Option
import SwiftUI
import SwiftData

struct MenuBarView: View {
    @StateObject private var backupManager: BackupManager
    @ObservedObject var logManager: LogManager
    @State private var timer: Timer?
    @State private var showingForceBackupConfirmation = false
    @State private var showingConfigurationAlert = false
    @Environment(\.openWindow) private var openWindow
    
    init(modelContainer: ModelContainer, logManager: LogManager) {
        self._backupManager = StateObject(wrappedValue: BackupManager(modelContainer: modelContainer, logManager: logManager))
        self.logManager = logManager
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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
            
            // Backup Actions
            VStack(alignment: .leading, spacing: 4) {
                Button(action: {
                    Task {
                        let settings = await backupManager.getOrCreateSettings()
                        let validation = settings.validateConfiguration()
                        if !validation.isValid {
                            showingConfigurationAlert = true
                        } else {
                            await backupManager.runBackup()
                        }
                    }
                }) {
                    HStack {
                        Image(systemName: "arrow.clockwise")
                        Text("Run Scheduled Backup")
                    }
                }
                .disabled(backupManager.isRunning)
                .help("Runs backup only if enough time has passed since last backup")
                
                Button(action: {
                    Task {
                        let settings = await backupManager.getOrCreateSettings()
                        let validation = settings.validateConfiguration()
                        if !validation.isValid {
                            showingConfigurationAlert = true
                        } else {
                            logManager.log("User clicked Force Backup Now", level: .debug)
                            if let lastBackup = backupManager.lastBackupTime {
                                // Show confirmation if there was a recent backup
                                let hoursSince = Date().timeIntervalSince(lastBackup) / 3600
                                if hoursSince < 1 {
                                    showingForceBackupConfirmation = true
                                } else {
                                    await backupManager.runForceBackup()
                                }
                            } else {
                                await backupManager.runForceBackup()
                            }
                        }
                    }
                }) {
                    HStack {
                        Image(systemName: "bolt.fill")
                        Text("Force Backup Now")
                    }
                }
                .disabled(backupManager.isRunning)
                .help("Immediately runs backup, ignoring schedule")
            }
            
            Divider()
            
            Button("Test Connection") {
                Task {
                    await backupManager.runConnectionTest()
                }
            }
            .disabled(backupManager.connectionStatus == .testing)
            
            Divider()
            
            // Window Actions
            Button("View History") {
                openWindow(id: "history")
            }
            
            Button("View Log") {
                openWindow(id: "log")
            }
            
            Button("Settings") {
                openWindow(id: "settings")
            }
            
            #if DEBUG
            Divider()
            
            Button("🔍 Debug Connection") {
                Task {
                    await backupManager.debugConnection()
                }
            }
            
            Button("🔧 Debug rclone Config") {
                Task {
                    await backupManager.debugRcloneConfig()
                }
            }
            
            Button("🔐 Debug Password") {
                Task {
                    await backupManager.debugPasswordHandling()
                }
            }
            #endif
            
            Divider()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .alert("Configuration Required", isPresented: $showingConfigurationAlert) {
            Button("Open Settings") {
                openWindow(id: "settings")
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Please configure your backup settings first. You need to set the source folder and destination.")
        }
        .alert("Force Backup", isPresented: $showingForceBackupConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Force Backup", role: .destructive) {
                Task {
                    await backupManager.runForceBackup()
                }
            }
        } message: {
            if let lastBackup = backupManager.lastBackupTime {
                let minutesAgo = Int(Date().timeIntervalSince(lastBackup) / 60)
                if minutesAgo < 60 {
                    Text("Last backup was \(minutesAgo) minute\(minutesAgo == 1 ? "" : "s") ago. Are you sure you want to force another backup now?")
                } else {
                    let hoursAgo = minutesAgo / 60
                    Text("Last backup was \(hoursAgo) hour\(hoursAgo == 1 ? "" : "s") ago. Are you sure you want to force another backup now?")
                }
            } else {
                Text("Are you sure you want to force a backup now?")
            }
        }
        .onAppear {
            startPeriodicBackup()
        }
        .onDisappear {
            timer?.invalidate()
        }
    }
    
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
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task {
                // This runs the regular backup (checks schedule)
                await backupManager.runBackup()
            }
        }
    }
}
