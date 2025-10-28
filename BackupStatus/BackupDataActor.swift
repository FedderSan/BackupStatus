//
//  BackupDataActor.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 26/07/2025.
//

import Foundation
import SwiftData
import Network

// MARK: - Database Actor (Thread-Safe Database Operations)

@ModelActor
actor BackupDataActor {
    func createBackupSession() -> PersistentIdentifier {
        let session = BackupSession()
        modelContext.insert(session)
        
        // Save immediately to ensure the session is persisted
        do {
            try modelContext.save()
        } catch {
            print("Failed to save backup session: \(error)")
        }
        
        return session.persistentModelID
    }
    
    func updateSession(_ sessionID: PersistentIdentifier,
                      success: Bool,
                      error: String?,
                      filesCount: Int,
                      totalSize: Int64) throws {
        // Fetch the session fresh from the context
        guard let session = self[sessionID, as: BackupSession.self] else {
            print("❌ Session not found for identifier: \(sessionID)")
            throw BackupError.sessionNotFound
        }
        
        session.endTime = Date()
        session.status = success ? .success : .failed
        session.errorMessage = error
        session.filesBackedUp = filesCount
        session.totalSize = totalSize
        
        try modelContext.save()
    }
    
    func updateSessionStatus(_ sessionID: PersistentIdentifier, status: BackupStatus, error: String? = nil) throws {
        // Fetch the session fresh from the context
        guard let session = self[sessionID, as: BackupSession.self] else {
            print("❌ Session not found for identifier: \(sessionID)")
            throw BackupError.sessionNotFound
        }
        
        session.endTime = Date()
        session.status = status
        session.errorMessage = error
        
        try modelContext.save()
    }
    
    func getSettings() -> BackupSettings? {
        let descriptor = FetchDescriptor<BackupSettings>()
        return try? modelContext.fetch(descriptor).first
    }
    
    func getOrCreateSettings() -> BackupSettings {
        if let existing = getSettings() {
            return existing
        } else {
            let settings = BackupSettings()
            modelContext.insert(settings)
            try? modelContext.save()
            return settings
        }
    }
    
    func updateLastSuccessfulBackup() throws {
        let settings = getOrCreateSettings()
        settings.lastSuccessfulBackup = Date()
        try modelContext.save()
    }
    
    func getRecentSessions(limit: Int = 10) -> [BackupSession] {
        var descriptor = FetchDescriptor<BackupSession>(
            sortBy: [SortDescriptor(\.startTime, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    // MARK: - Automatic Cleanup (runs in background)
    
    /// Automatically cleans old sessions based on retention period
    /// This should be called periodically (e.g., after each backup or on startup)
    func cleanOldSessions(retentionDays: Int = 90) {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -retentionDays, to: Date()) ?? Date()
        
        var descriptor = FetchDescriptor<BackupSession>(
            predicate: #Predicate<BackupSession> { session in
                session.startTime < cutoffDate
            }
        )
        
        if let oldSessions = try? modelContext.fetch(descriptor) {
            let count = oldSessions.count
            
            if count > 0 {
                for session in oldSessions {
                    modelContext.delete(session)
                }
                
                do {
                    try modelContext.save()
                    print("🧹 Auto-cleaned \(count) session(s) older than \(retentionDays) days")
                } catch {
                    print("❌ Failed to clean old sessions: \(error)")
                }
            }
        }
    }
    
    /// Gets the total count of all sessions
    func getTotalSessionCount() -> Int {
        let descriptor = FetchDescriptor<BackupSession>()
        return (try? modelContext.fetch(descriptor).count) ?? 0
    }
}
