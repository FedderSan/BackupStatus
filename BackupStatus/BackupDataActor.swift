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
    func createBackupSession() -> BackupSession {
        let session = BackupSession()
        modelContext.insert(session)
        return session
    }
    
    func updateSession(_ sessionID: PersistentIdentifier,
                      success: Bool,
                      error: String?,
                      filesCount: Int,
                      totalSize: Int64) throws {
        guard let session = modelContext.model(for: sessionID) as? BackupSession else {
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
        guard let session = modelContext.model(for: sessionID) as? BackupSession else {
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
    
    func cleanOldSessions() {
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        
        var descriptor = FetchDescriptor<BackupSession>(
            predicate: #Predicate<BackupSession> { session in
                session.startTime < cutoffDate
            }
        )
        
        if let oldSessions = try? modelContext.fetch(descriptor) {
            for session in oldSessions {
                modelContext.delete(session)
            }
            try? modelContext.save()
        }
    }
}






