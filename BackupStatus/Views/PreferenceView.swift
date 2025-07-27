//
//  PreferenceView.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 27/07/2025.
//
import SwiftUI
import SwiftData
// For SwiftUI-based preferences window (future enhancement)
struct PreferencesView: View {
    @State private var serverHost = "MiniServer-DF"
    @State private var serverPort = "8081"
    @State private var backupInterval = 60
    
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
                        Text("Check interval (minutes):")
                        TextField("Interval", value: $backupInterval, format: .number)
                    }
                }
            }
            
            HStack {
                Spacer()
                Button("Cancel") {
                    // Close window
                }
                Button("Save") {
                    // Save preferences
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(width: 400, height: 300)
    }
}
