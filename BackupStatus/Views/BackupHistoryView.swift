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
    
    @State private var showingCleanConfirmation = false
    @State private var cleanedCount = 0
    
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
                    showingCleanConfirmation = true
                }) {
                    Label("Clean Old Sessions", systemImage: "trash")
                }
                .disabled(sessions.isEmpty)
            }
        }
        .alert("Clean Old Sessions?", isPresented: $showingCleanConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                cleanOldSessions()
            }
        } message: {
            let oldCount = countOldSessions()
            if oldCount > 0 {
                Text("This will delete \(oldCount) session(s) older than 30 days.")
            } else {
                Text("No sessions older than 30 days found.")
            }
        }
        .alert("Sessions Cleaned", isPresented: .constant(cleanedCount > 0)) {
            Button("OK") {
                cleanedCount = 0
            }
        } message: {
            Text("Successfully deleted \(cleanedCount) old session(s).")
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
    
    private func countOldSessions() -> Int {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        return sessions.filter { $0.startTime < cutoffDate }.count
    }
    
    private func cleanOldSessions() {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        
        var deletedCount = 0
        for session in sessions where session.startTime < cutoffDate {
            modelContext.delete(session)
            deletedCount += 1
        }
        
        // CRITICAL FIX: Save the context after deletion
        do {
            try modelContext.save()
            cleanedCount = deletedCount
            print("✅ Successfully cleaned \(deletedCount) old sessions")
        } catch {
            print("❌ Failed to save after cleaning sessions: \(error)")
        }
    }
}
