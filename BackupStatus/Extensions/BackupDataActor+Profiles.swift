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
        // Find the profile by ID in the current context
        let profileId = profile.id
        if let profileToDelete = try? modelContext.fetch(
            FetchDescriptor<BackupProfile>(
                predicate: #Predicate<BackupProfile> { p in
                    p.id == profileId
                }
            )
        ).first {
            modelContext.delete(profileToDelete)
            try? modelContext.save()
        }
    }
    
    func updateProfileStats(_ profile: BackupProfile, filesCount: Int, totalSize: Int64) {
        // Find the profile by ID in the current context
        let profileId = profile.id
        if let profileToUpdate = try? modelContext.fetch(
            FetchDescriptor<BackupProfile>(
                predicate: #Predicate<BackupProfile> { p in
                    p.id == profileId
                }
            )
        ).first {
            profileToUpdate.lastSuccessfulBackup = Date()
            profileToUpdate.totalBackupsRun += 1
            profileToUpdate.lastBackupFilesCount = filesCount
            profileToUpdate.lastBackupSize = totalSize
            
            try? modelContext.save()
        }
    }
    
    func getProfile(byId id: UUID) -> BackupProfile? {
        let descriptor = FetchDescriptor<BackupProfile>(
            predicate: #Predicate<BackupProfile> { profile in
                profile.id == id
            }
        )
        
        return try? modelContext.fetch(descriptor).first
    }
}
