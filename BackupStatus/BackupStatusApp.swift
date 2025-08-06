//
//  BackupStatusApp.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 26/07/2025.
//

import SwiftUI
import SwiftData

// MARK: - Enhanced App with SwiftData and Log Window
@main
struct BackupStatusApp: App {
    let modelContainer: ModelContainer
    @StateObject private var logManager = LogManager()
    
    init() {
        
        // Define schema
            let schema = Schema([BackupSession.self, BackupSettings.self])
            let config = ModelConfiguration("Default", schema: schema)

        let storeURL = config.url // this gives '.../default.store'
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
        
        
        
        do {
            modelContainer = try ModelContainer(for: BackupSession.self, BackupSettings.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
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
        .defaultSize(width: 800, height: 600)
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
