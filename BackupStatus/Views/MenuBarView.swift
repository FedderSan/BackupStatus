// MARK: - Updated MenuBarView
import SwiftUI
import SwiftData

struct MenuBarView: View {
    @StateObject private var backupManager: BackupManager
    @State private var timer: Timer?
    @Environment(\.openWindow) private var openWindow
    
    init(modelContainer: ModelContainer) {
        self._backupManager = StateObject(wrappedValue: BackupManager(modelContainer: modelContainer))
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
            
            Button("Run Backup Now") {
                Task {
                    await backupManager.runBackup()
                }
            }
            .disabled(backupManager.isRunning)
            
            Button("Test Connection") {
                Task {
                    await backupManager.runConnectionTest()
                }
            }
            .disabled(backupManager.connectionStatus == .testing)
            
            Button("View History") {
                openWindow(id: "history")
            }
            
            Button("Settings") {
                openWindow(id: "settings")
            }
            
            Divider()
            
            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
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
                await backupManager.runBackup()
            }
        }
    }
}
