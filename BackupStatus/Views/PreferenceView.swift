//
//  PreferenceView.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 27/07/2025.
//
import SwiftUI
import SwiftData

// For SwiftUI-based preferences window
@MainActor
struct PreferencesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var serverHost = "MiniServer-DF"
    @State private var serverPort = "8081"
    @State private var backupInterval = 1
    @State private var settings: BackupSettings?
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Backup Preferences")
                .font(.title2)
                .fontWeight(.bold)
            
            Form {
                Section("Server Settings") {
                    HStack {
                        Text("Host:")
                        TextField("Server Host", text: $serverHost)
                    }
                    HStack {
                        Text("Port:")
                        TextField("Port", text: $serverPort)
                    }
                }
                
                Section("Backup Settings") {
                    HStack {
                        Text("Check interval (hours):")
                        TextField("Interval", value: $backupInterval, format: .number)
                    }
                }
            }
            
            HStack {
                Spacer()
                Button("Cancel") {
                    loadSettings() // Reset to original values
                }
                Button("Save") {
                    saveSettings()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400, height: 300)
        .onAppear {
            loadSettings()
        }
    }
    
    private func loadSettings() {
        let descriptor = FetchDescriptor<BackupSettings>()
        if let existingSettings = try? modelContext.fetch(descriptor).first {
            settings = existingSettings
            serverHost = existingSettings.serverHost
            serverPort = String(existingSettings.serverPort)
            backupInterval = existingSettings.backupIntervalHours
        } else {
            // Create default settings
            let newSettings = BackupSettings()
            modelContext.insert(newSettings)
            settings = newSettings
            serverHost = newSettings.serverHost
            serverPort = String(newSettings.serverPort)
            backupInterval = newSettings.backupIntervalHours
        }
    }
    
    private func saveSettings() {
        guard let settings = settings else { return }
        
        settings.serverHost = serverHost
        settings.serverPort = Int(serverPort) ?? 8081
        settings.backupIntervalHours = backupInterval
        
        do {
            try modelContext.save()
            print("Settings saved successfully")
        } catch {
            print("Failed to save settings: \(error)")
        }
    }
}
