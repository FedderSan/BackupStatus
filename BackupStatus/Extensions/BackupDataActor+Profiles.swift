//
//  BackupDataActor+Profiles.swift
//  BackupStatus
//
//  Profile management methods for BackupDataActor
//

import Foundation
import SwiftData

extension BackupDataActor {
    
    // MARK: - Profile Management
    
    func getAllProfiles() -> [BackupProfile] {
        let descriptor = FetchDescriptor<BackupProfile>(
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    func getEnabledProfiles() -> [BackupProfile] {
        let descriptor = FetchDescriptor<BackupProfile>(
            predicate: #Predicate<BackupProfile> { profile in
                profile.isEnabled == true
            },
            sortBy: [SortDescriptor(\.name, order: .forward)]
        )
        
        return (try? modelContext.fetch(descriptor)) ?? []
    }
    
    func createProfile(name: String, type: BackupProfileType) -> BackupProfile {
        let profile = BackupProfile(name: name, profileType: type)
        modelContext.insert(profile)
        
        do {
            try modelContext.save()
        } catch {
            print("Failed to create profile: \(error)")
        }
        
        return profile
    }
    
    func deleteProfile(_ profile: BackupProfile) {
        // Delete the profile directly - SwiftData will handle it
        modelContext.delete(profile)
        try? modelContext.save()
    }
    
    func updateProfileStats(_ profile: BackupProfile, filesCount: Int, totalSize: Int64) {
        // Update the profile directly - it's already in the context
        profile.lastSuccessfulBackup = Date()
        profile.totalBackupsRun += 1
        profile.lastBackupFilesCount = filesCount
        profile.lastBackupSize = totalSize
        
        try? modelContext.save()
    }
    
    func getProfile(byName name: String) -> BackupProfile? {
        let descriptor = FetchDescriptor<BackupProfile>(
            predicate: #Predicate<BackupProfile> { profile in
                profile.name == name
            }
        )
        
        return try? modelContext.fetch(descriptor).first
    }
}
