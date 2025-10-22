//
//  BackupProfileTypeModel.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 22/10/2025.
//

import SwiftData
import Foundation



// MARK: - Backup Profile Model
@Model
class BackupProfile {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var profileType: BackupProfileType
    
    // Source Configuration
    var sourcePath: String
    var excludePatterns: String  // Comma-separated patterns
    
    // Destination Configuration (local only for now)
    var destinationPath: String
    
    // Versioned Backup Settings (only for versioned type)
    var createVersions: Bool
    var versionRetentionCount: Int  // Store as int for SwiftData
    
    // One-Way Sync Settings (only for oneWaySync type)
    var useTrashFolder: Bool
    var trashFolderName: String
    var autoEmptyTrash: Bool
    var trashRetentionDays: Int
    
    // Schedule
    var backupIntervalHours: Int
    var lastSuccessfulBackup: Date?
    
    // Statistics
    var totalBackupsRun: Int
    var lastBackupFilesCount: Int
    var lastBackupSize: Int64
    
    var versionRetention: BackupVersionRetention {
        get {
            return BackupVersionRetention(rawValue: versionRetentionCount) ?? .versions14
        }
        set {
            versionRetentionCount = newValue.rawValue
        }
    }
    
    init(name: String, profileType: BackupProfileType) {
        self.id = UUID()
        self.name = name
        self.isEnabled = true
        self.profileType = profileType
        
        // Source defaults
        self.sourcePath = ""
        self.excludePatterns = ".DS_Store,*.tmp,*.cache"
        
        // Destination defaults
        self.destinationPath = ""
        
        // Versioned backup defaults
        self.createVersions = (profileType == .versioned)
        self.versionRetentionCount = BackupVersionRetention.versions14.rawValue
        
        // One-way sync defaults
        self.useTrashFolder = (profileType == .oneWaySync)
        self.trashFolderName = ".backup_trash"
        self.autoEmptyTrash = false
        self.trashRetentionDays = 30
        
        // Schedule defaults
        self.backupIntervalHours = 24
        
        // Statistics
        self.totalBackupsRun = 0
        self.lastBackupFilesCount = 0
        self.lastBackupSize = 0
    }
    
    // MARK: - Path Helpers
    
    var fullSourcePath: String {
        return sourcePath.hasSuffix("/") ? sourcePath : sourcePath + "/"
    }
    
    var fullDestinationPath: String {
        return destinationPath.hasSuffix("/") ?
            String(destinationPath.dropLast()) :
            destinationPath
    }
    
    var excludeArray: [String] {
        return excludePatterns
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
    
    func latestPath() -> String {
        return "\(fullDestinationPath)/latest"
    }
    
    func versionPath(for date: Date = Date()) -> String {
        guard createVersions else { return latestPath() }
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let dateString = dateFormatter.string(from: date)
        return "\(fullDestinationPath)/versions/\(dateString)"
    }
    
    func trashPath() -> String {
        return "\(fullDestinationPath)/\(trashFolderName)"
    }
    
    func versionsDirectoryPath() -> String {
        return "\(fullDestinationPath)/versions"
    }
    
    // MARK: - Validation
    
    func validateConfiguration() -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        
        if name.isEmpty {
            errors.append("Profile name is required")
        }
        
        if sourcePath.isEmpty {
            errors.append("Source path is required")
        } else {
            var isDirectory: ObjCBool = false
            if !FileManager.default.fileExists(atPath: sourcePath, isDirectory: &isDirectory) {
                errors.append("Source path does not exist")
            } else if !isDirectory.boolValue {
                errors.append("Source path is not a directory")
            } else if !FileManager.default.isReadableFile(atPath: sourcePath) {
                errors.append("Source path is not readable")
            }
        }
        
        if destinationPath.isEmpty {
            errors.append("Destination path is required")
        } else {
            var isDirectory: ObjCBool = false
            if !FileManager.default.fileExists(atPath: destinationPath, isDirectory: &isDirectory) {
                errors.append("Destination path does not exist")
            } else if !isDirectory.boolValue {
                errors.append("Destination path is not a directory")
            } else if !FileManager.default.isWritableFile(atPath: destinationPath) {
                errors.append("Destination path is not writable")
            }
        }
        
        if sourcePath == destinationPath {
            errors.append("Source and destination cannot be the same")
        }
        
        if backupIntervalHours < 1 {
            errors.append("Backup interval must be at least 1 hour")
        }
        
        return (errors.isEmpty, errors)
    }
    
    // MARK: - Version Management (for versioned profiles)
    
    func getExistingVersions() -> [String] {
        guard profileType == .versioned else { return [] }
        
        let versionsDir = versionsDirectoryPath()
        
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: versionsDir) else {
            return []
        }
        
        return contents
            .filter { item in
                var isDirectory: ObjCBool = false
                let fullPath = "\(versionsDir)/\(item)"
                return FileManager.default.fileExists(atPath: fullPath, isDirectory: &isDirectory) && isDirectory.boolValue
            }
            .sorted()
    }
    
    func shouldCleanupVersions() -> Bool {
        guard profileType == .versioned else { return false }
        return versionRetention.shouldCleanup
    }
    
    func getVersionsToCleanup() -> [String] {
        guard shouldCleanupVersions() else { return [] }
        
        let existingVersions = getExistingVersions()
        let maxVersions = versionRetention.rawValue
        
        guard existingVersions.count > maxVersions else { return [] }
        
        let versionsToDelete = existingVersions.count - maxVersions
        return Array(existingVersions.prefix(versionsToDelete))
    }
    
    // MARK: - Trash Management (for oneWaySync profiles)
    
    func getTrashItems() -> [(name: String, date: Date, size: Int64)] {
        guard profileType == .oneWaySync && useTrashFolder else { return [] }
        
        let trashDir = trashPath()
        
        guard let contents = try? FileManager.default.contentsOfDirectory(atPath: trashDir) else {
            return []
        }
        
        return contents.compactMap { item in
            let fullPath = "\(trashDir)/\(item)"
            guard let attributes = try? FileManager.default.attributesOfItem(atPath: fullPath),
                  let modDate = attributes[.modificationDate] as? Date,
                  let size = attributes[.size] as? Int64 else {
                return nil
            }
            return (item, modDate, size)
        }
    }
    
    func getTrashItemsToCleanup() -> [String] {
        guard profileType == .oneWaySync && useTrashFolder && autoEmptyTrash else {
            return []
        }
        
        let cutoffDate = Calendar.current.date(byAdding: .day, value: -trashRetentionDays, to: Date()) ?? Date()
        let items = getTrashItems()
        
        return items
            .filter { $0.date < cutoffDate }
            .map { $0.name }
    }
    
    func shouldCleanupTrash() -> Bool {
        return profileType == .oneWaySync && useTrashFolder && autoEmptyTrash
    }
}
