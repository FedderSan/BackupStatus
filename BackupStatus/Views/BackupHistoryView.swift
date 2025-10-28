//
//  BackupHistoryView.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 26/07/2025.
//

import SwiftUI
import SwiftData

struct BackupHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BackupSession.startTime, order: .reverse)
    private var sessions: [BackupSession]
    
    @State private var showingClearConfirmation = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with info
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Backup History")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    Text("\(sessions.count) total sessions")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding()
            
            Divider()
            
            // Sessions table
            if sessions.isEmpty {
                ContentUnavailableView(
                    "No Backup History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Run a backup to see history here")
                )
            } else {
                Table(sessions) {
                    TableColumn("Date") { session in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.startTime.formatted(date: .abbreviated, time: .shortened))
                                .font(.body)
                            Text(session.startTime, style: .relative)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .width(min: 150, max: 200)
                    
                    TableColumn("Status") { session in
                        HStack {
                            Circle()
                                .fill(statusColor(session.status))
                                .frame(width: 8, height: 8)
                            Text(session.status.rawValue.capitalized)
                                .foregroundColor(statusColor(session.status))
                        }
                    }
                    .width(min: 100, max: 150)
                    
                    TableColumn("Files") { session in
                        Text("\(session.filesBackedUp)")
                    }
                    .width(min: 60, max: 100)
                    
                    TableColumn("Size") { session in
                        Text(ByteCountFormatter.string(fromByteCount: session.totalSize, countStyle: .file))
                    }
                    .width(min: 80, max: 120)
                    
                    TableColumn("Duration") { session in
                        if let endTime = session.endTime {
                            let duration = endTime.timeIntervalSince(session.startTime)
                            Text(formatDuration(duration))
                        } else {
                            Text("Running...")
                                .foregroundColor(.blue)
                        }
                    }
                    .width(min: 80, max: 120)
                    
                    TableColumn("Error") { session in
                        if let error = session.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                                .lineLimit(2)
                        } else {
                            Text("—")
                                .foregroundColor(.secondary)
                        }
                    }
                    .width(min: 150)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: {
                    showingClearConfirmation = true
                }) {
                    Label("Clear All History", systemImage: "trash")
                }
                .foregroundColor(.red)
                .disabled(sessions.isEmpty)
            }
        }
        .alert("Clear All History?", isPresented: $showingClearConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Clear All", role: .destructive) {
                clearAllSessions()
            }
        } message: {
            Text("This will permanently delete all \(sessions.count) backup session(s) from history. Your actual backup files will not be affected.")
        }
    }
    
    // MARK: - Helper Methods
    
    private func statusColor(_ status: BackupStatus) -> Color {
        switch status {
        case .success: return .green
        case .failed: return .red
        case .connectionError: return .orange
        case .running: return .blue
        case .skipped: return .gray
        }
    }
    
    private func formatDuration(_ duration: TimeInterval) -> String {
        let hours = Int(duration) / 3600
        let minutes = Int(duration) / 60 % 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%dh %dm %ds", hours, minutes, seconds)
        } else if minutes > 0 {
            return String(format: "%dm %ds", minutes, seconds)
        } else {
            return String(format: "%ds", seconds)
        }
    }
    
    private func clearAllSessions() {
        let count = sessions.count
        
        // Delete all sessions
        for session in sessions {
            modelContext.delete(session)
        }
        
        // Save the context
        do {
            try modelContext.save()
            print("✅ Successfully cleared \(count) session(s) from history")
        } catch {
            print("❌ Failed to save after clearing sessions: \(error)")
        }
    }
}
