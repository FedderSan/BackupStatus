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
        
        Window("Settings", id: "settings") {
            PreferencesView()
                .modelContainer(modelContainer)
        }
        .windowResizability(.contentSize)
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
