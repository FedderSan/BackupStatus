import SwiftUI
import SwiftData

// MARK: - Application Support Directory Extension
extension URL {
    static var applicationSupportDirectory: URL {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        return paths.first!
    }
}

// MARK: - Enhanced App with SwiftData and Persistent Logs
@main
struct BackupStatusApp: App {
    let modelContainer: ModelContainer
    let logManager: LogManager  // Changed from @StateObject to regular property
    
    init() {
        // Define schema - Include all models for persistence
        let schema = Schema([
            BackupSession.self,
            BackupSettings.self,
            PersistentLogEntry.self,  // Add this for persistent logs
            BackupProfile.self  // ADD THIS
        ])
        
        // Create configuration with explicit store location in Application Support
        let appSupportURL = URL.applicationSupportDirectory
            .appendingPathComponent("BackupStatus", isDirectory: true)
        
        // Ensure the directory exists
        do {
            try FileManager.default.createDirectory(at: appSupportURL, withIntermediateDirectories: true)
        } catch {
            print("Failed to create app support directory: \(error)")
        }
        
        let storeURL = appSupportURL.appendingPathComponent("BackupStatus.store")
        let config = ModelConfiguration(url: storeURL)
        
        // DEBUGGING: Print database location
        print("📁 Database location: \(storeURL.path)")
        print("📁 App Support directory: \(appSupportURL.path)")
        
        // COMMENTED OUT: Database deletion code (for development only)
        // Uncomment ONLY during development if you need to reset the database
        // WARNING: This will delete all your backup history and settings!
        /*
        print("🗑️ DEVELOPMENT MODE: Deleting existing database files")
        let baseURL = storeURL.deletingPathExtension()
        let extensions = ["store", "store-shm", "store-wal"]

        for ext in extensions {
            let fileURL = baseURL.appendingPathExtension(ext)
            if FileManager.default.fileExists(atPath: fileURL.path) {
                do {
                    try FileManager.default.removeItem(at: fileURL)
                    print("Deleted: \(fileURL.lastPathComponent)")
                } catch {
                    print("Error deleting \(fileURL.lastPathComponent): \(error)")
                }
            }
        }
        */
        
        do {
            self.modelContainer = try ModelContainer(for: schema, configurations: [config])
            print("✅ ModelContainer created successfully")
            
            // Verify database file was created
            if FileManager.default.fileExists(atPath: storeURL.path) {
                let attributes = try? FileManager.default.attributesOfItem(atPath: storeURL.path)
                if let size = attributes?[.size] as? Int64 {
                    print("📊 Database file size: \(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))")
                }
            } else {
                print("⚠️ Database file does not exist yet (will be created on first write)")
            }
            
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
        
        // Create LogManager directly without @StateObject wrapper
        self.logManager = LogManager(modelContainer: self.modelContainer)
    }
    
    var body: some Scene {
        MenuBarExtra("Backup Status", systemImage: dynamicMenuBarIcon) {
            MenuBarView(modelContainer: modelContainer, logManager: logManager)
        }
        .menuBarExtraStyle(.menu)
        
        Window("Backup History", id: "history") {
            BackupHistoryView()
                .modelContainer(modelContainer)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 800, height: 500)
        
        Window("Settings", id: "settings") {
            PreferencesView()
                .modelContainer(modelContainer)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 800, height: 700)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        
        Window("Backup Log", id: "log") {
            LogView(logManager: logManager)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 900, height: 600)
        
        Window("Debug", id: "debug") {
            DebugView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 800, height: 600)
        
        // In BackupStatusApp.swift, add a new window:
        Window("Backup Profiles", id: "profiles") {
            ProfileManagementView()
                .modelContainer(modelContainer)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 900, height: 600)
    }
    
    private var dynamicMenuBarIcon: String {
        switch logManager.currentBackupStatus {
        case .success:
            return "externaldrive.badge.checkmark"
        case .connectionError:
            return "externaldrive.badge.wifi"
        case .failed:
            return "externaldrive.badge.xmark"
        case .running:
            return "externaldrive.badge.timemachine"
        case .skipped:
            return "externaldrive.badge.questionmark"
        }
    }
}
