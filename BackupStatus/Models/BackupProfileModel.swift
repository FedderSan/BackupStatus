//
//  BackupProfileModel.swift
//  BackupStatus
//
//  Enhanced with WebDAV support
//

import SwiftData
import Foundation

// MARK: - Backup Profile Model
@Model
class BackupProfile {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var profileTypeRaw: String  // versioned or oneWaySync
    
    // NEW: Remote Type
    var remoteTypeRaw: String  // local or webdav
    
    // Source Configuration
    var sourcePath: String
    var excludePatterns: String
    
    // Local Destination Configuration
    var destinationPath: String
    
    // NEW: WebDAV Configuration
    var webdavServerHost: String
    var webdavServerPort: Int
    var webdavUseHTTPS: Bool
    var webdavVerifySSL: Bool
    var webdavURL: String  // Base URL path like /remote.php/dav/files/username
    var webdavPath: String  // Backup path within WebDAV
    var webdavUsername: String
    var webdavPasswordObscured: String
    var webdavRemoteName: String  // For rclone config
    
    // Versioned Backup Settings
    var createVersions: Bool
    var versionRetentionCount: Int
    
    // One-Way Sync Settings
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
    
    // Computed property for profileType
    var profileType: BackupProfileType {
        get {
            return BackupProfileType(rawValue: profileTypeRaw) ?? .versioned
        }
        set {
            profileTypeRaw = newValue.rawValue
        }
    }
    
    // NEW: Computed property for remoteType
    var remoteType: ProfileRemoteType {
        get {
            return ProfileRemoteType(rawValue: remoteTypeRaw) ?? .local
        }
        set {
            remoteTypeRaw = newValue.rawValue
        }
    }
    
    var versionRetention: BackupVersionRetention {
        get {
            return BackupVersionRetention(rawValue: versionRetentionCount) ?? .versions14
        }
        set {
            versionRetentionCount = newValue.rawValue
        }
    }
    
    init(name: String, profileType: BackupProfileType, remoteType: ProfileRemoteType = .local) {
        self.id = UUID()
        self.name = name
        self.isEnabled = true
        self.profileTypeRaw = profileType.rawValue
        self.remoteTypeRaw = remoteType.rawValue
        
        // Source defaults
        self.sourcePath = ""
        self.excludePatterns = ".DS_Store,*.tmp,*.cache"
        
        // Destination defaults
        self.destinationPath = ""
        
        // WebDAV defaults
        self.webdavServerHost = ""
        self.webdavServerPort = 443
        self.webdavUseHTTPS = true
        self.webdavVerifySSL = true
        self.webdavURL = "/remote.php/dav/files/"
        self.webdavPath = "Backups"
        self.webdavUsername = ""
        self.webdavPasswordObscured = ""
        self.webdavRemoteName = "backup-\(UUID().uuidString.prefix(8))"
        
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
        switch remoteType {
        case .local:
            return destinationPath.hasSuffix("/") ?
                String(destinationPath.dropLast()) :
                destinationPath
        case .webdav:
            // For WebDAV, return the rclone remote path
            let cleanPath = webdavPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return "\(webdavRemoteName):\(cleanPath)"
        }
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
    
    // MARK: - WebDAV Helpers
    
    var fullWebDAVURL: String {
        let scheme = webdavUseHTTPS ? "https" : "http"
        let port = webdavServerPort != (webdavUseHTTPS ? 443 : 80) ? ":\(webdavServerPort)" : ""
        let cleanURL = webdavURL.hasPrefix("/") ? webdavURL : "/\(webdavURL)"
        
        return "\(scheme)://\(webdavServerHost)\(port)\(cleanURL)"
    }
    
    func setPassword(_ plainPassword: String) async {
        if let obscured = await RclonePasswordHelper.shared.obscurePassword(plainPassword) {
            self.webdavPasswordObscured = obscured
        } else {
            print("Failed to obscure password")
            self.webdavPasswordObscured = ""
        }
    }
    
    func getPlainPassword() async -> String? {
        guard !webdavPasswordObscured.isEmpty else { return nil }
        return await RclonePasswordHelper.shared.revealPassword(webdavPasswordObscured)
    }
    
    func generateRcloneConfig() -> String {
        var config = """
        [\(webdavRemoteName)]
        type = webdav
        url = \(fullWebDAVURL)
        vendor = nextcloud
        user = \(webdavUsername)
        pass = \(webdavPasswordObscured)
        """
        
        if !webdavVerifySSL || !webdavUseHTTPS {
            config += "\ninsecure_skip_verify = true"
        }
        
        return config
    }
    
    // MARK: - Validation
    
    func validateConfiguration() -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        
        if name.isEmpty {
            errors.append("Profile name is required")
        }
        
        // Source validation
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
        
        // Destination validation based on remote type
        switch remoteType {
        case .local:
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
                
                if sourcePath == destinationPath {
                    errors.append("Source and destination cannot be the same")
                }
            }
            
        case .webdav:
            if webdavServerHost.isEmpty {
                errors.append("WebDAV server host is required")
            }
            if webdavUsername.isEmpty {
                errors.append("WebDAV username is required")
            }
            if webdavPasswordObscured.isEmpty {
                errors.append("WebDAV password is required")
            }
            if webdavPath.isEmpty {
                errors.append("WebDAV backup path is required")
            }
        }
        
        if backupIntervalHours < 1 {
            errors.append("Backup interval must be at least 1 hour")
        }
        
        return (errors.isEmpty, errors)
    }
    
    // MARK: - Version Management
    
    func getExistingVersions() -> [String] {
        guard profileType == .versioned else { return [] }
        guard remoteType == .local else { return [] } // WebDAV version listing needs rclone
        
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
    
    // MARK: - Trash Management
    
    func getTrashItems() -> [(name: String, date: Date, size: Int64)] {
        guard profileType == .oneWaySync && useTrashFolder else { return [] }
        guard remoteType == .local else { return [] } // WebDAV trash listing needs rclone
        
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
