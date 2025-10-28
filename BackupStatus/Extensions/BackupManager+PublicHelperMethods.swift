//
//  BackupManager+PublicHelperMethods.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 21/10/2025.
//

// MARK: - Public Helper Methods
import Foundation

extension BackupManager {
    func getSettings() async -> BackupSettings? {
        return await dataActor.getSettings()
    }
    
    func getOrCreateSettings() async -> BackupSettings {
        return await dataActor.getOrCreateSettings()
    }
    
    func getRecentSessions(limit: Int = 10) async -> [BackupSession] {
        return await dataActor.getRecentSessions(limit: limit)
    }
    
    func cleanOldSessions() async {
        await dataActor.cleanOldSessions()
    }
}
