// MARK: - Updated MenuBarView
import SwiftUI
import SwiftData

struct MenuBarView: View {
    @State private var backupManager: BackupManager
    @State private var timer: Timer?
    @Environment(\.openWindow) private var openWindow
    
    init(modelContainer: ModelContainer) {
        self._backupManager = State(wrappedValue: BackupManager(modelContainer: modelContainer))
    }
    
    var body: some View {
        VStack {
            Text("Status: \(backupManager.currentStatus.rawValue.capitalized)")
                .font(.headline)
            
            if let lastBackup = backupManager.lastBackupTime {
                Text("Last: \(lastBackup.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
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
                    await backupManager.testConnection()
                    // You can add a public testConnection method if needed
                    print("Connection test would run here")
                }
            }
            
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
    
    private func startPeriodicBackup() {
        timer = Timer.scheduledTimer(withTimeInterval: 300, repeats: true) { _ in
            Task {
                await backupManager.runBackup()
            }
        }
    }
}	
