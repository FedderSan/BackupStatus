//
//  BackupStatusApp.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 26/07/2025.
//

import SwiftUI
import SwiftData

// MARK: - Enhanced App with SwiftData
@main
struct BackupStatusApp: App {
    let modelContainer: ModelContainer
    
    init() {
        do {
            modelContainer = try ModelContainer(for: BackupSession.self, BackupSettings.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }
    
    var body: some Scene {
        MenuBarExtra("Backup Status", systemImage: "externaldrive.badge.checkmark") {
            MenuBarView(modelContainer: modelContainer)
        }
        .menuBarExtraStyle(.menu)
        
        Window("Backup History", id: "history") {
            BackupHistoryView()
                .modelContainer(modelContainer)
        }
    }
}
