//
//  BackupStatusApp.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 26/07/2025.
//

// MARK: - SwiftUI Views for Settings and History
import SwiftUI
import SwiftData

import SwiftUI
import SwiftData

struct BackupHistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BackupSession.startTime, order: .reverse)
    private var sessions: [BackupSession]
    
    var body: some View {
        Table(sessions) {
            TableColumn("Date") { session in
                Text(session.startTime.formatted(date: .abbreviated, time: .shortened))
            }
            
            TableColumn("Status") { session in
                HStack {
                    Circle()
                        .fill(statusColor(session.status))
                        .frame(width: 8, height: 8)
                    Text(session.status.rawValue.capitalized)
                }
            }
            
            TableColumn("Files") { session in
                Text("\(session.filesBackedUp)")
            }
            
            TableColumn("Size") { session in
                Text(ByteCountFormatter.string(fromByteCount: session.totalSize, countStyle: .file))
            }
            
            TableColumn("Duration") { session in
                if let endTime = session.endTime {
                    let duration = endTime.timeIntervalSince(session.startTime)
                    Text("\(Int(duration))s")
                } else {
                    Text("Running...")
                }
            }
        }
        .navigationTitle("Backup History")
        .toolbar {
            Button("Clean Old") {
                cleanOldSessions()
            }
        }
    }
    
    private func statusColor(_ status: BackupStatus) -> Color {
        switch status {
        case .success: return .green
        case .failed: return .red
        case .connectionError: return .orange
        case .running: return .blue
        case .skipped: return .gray
        }
    }
    
    private func cleanOldSessions() {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        
        for session in sessions where session.startTime < cutoffDate {
            modelContext.delete(session)
        }
    }
}
