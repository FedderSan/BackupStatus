import SwiftData
import Foundation

@Model
class BackupSettings {
    var id: UUID
    var serverHost: String
    var serverPort: Int
    var backupIntervalHours: Int
    var lastSuccessfulBackup: Date?
    
    // DEPRECATED: These fields are kept for backward compatibility but should use profiles instead
    var sourcePath: String
    var excludePatterns: String
    
    // WebDAV Configuration (kept for future use)
    var webdavEnabled: Bool
    var webdavURL: String
    var webdavUsername: String
    var webdavPasswordObscured: String
    var webdavPath: String
    var webdavUseHTTPS: Bool
    var webdavVerifySSL: Bool
    
    // DEPRECATED: Use profiles instead
    var localDestinationPath: String
    var localCreateDatedFolders: Bool
    
    // Remote Configuration (kept for future use)
    var remoteName: String
    var remoteType: RemoteType
    
    // Log Management Settings (Still used globally)
    var logRetentionDays: Int
    
    // DEPRECATED: Use profile-specific retention instead
    var backupVersionRetentionCount: Int
    
    var logRetentionPeriod: LogRetentionPeriod {
        get {
            return LogRetentionPeriod(rawValue: logRetentionDays) ?? .days30
        }
        set {
            logRetentionDays = newValue.rawValue
        }
    }
    
    var backupVersionRetention: BackupVersionRetention {
        get {
            return BackupVersionRetention(rawValue: backupVersionRetentionCount) ?? .versions14
        }
        set {
            backupVersionRetentionCount = newValue.rawValue
        }
    }
    
    init() {
        self.id = UUID()
        self.serverHost = "MiniServer-DF"
        self.serverPort = 8081
        self.backupIntervalHours = 24
        
        // Source defaults (deprecated)
        self.sourcePath = ""
        self.excludePatterns = ".DS_Store,*.tmp,*.cache"
        
        // WebDAV defaults
        self.webdavEnabled = true
        self.webdavURL = "/remote.php/dav/files/daniel"
        self.webdavUsername = ""
        self.webdavPasswordObscured = ""
        self.webdavPath = ""
        self.webdavUseHTTPS = false
        self.webdavVerifySSL = true
        
        // Local defaults (deprecated)
        self.localDestinationPath = ""
        self.localCreateDatedFolders = true
        
        // Remote defaults
        self.remoteName = "backup-remote"
        self.remoteType = .local
        
        // Retention defaults
        self.logRetentionDays = LogRetentionPeriod.days30.rawValue
        self.backupVersionRetentionCount = BackupVersionRetention.versions14.rawValue
    }
    
    // MARK: - Source Path Helpers (Kept for migration/debugging)
    
    var fullSourcePath: String {
        return sourcePath.hasSuffix("/") ? sourcePath : sourcePath + "/"
    }
    
    var sourceExists: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: sourcePath, isDirectory: &isDirectory) && isDirectory.boolValue
    }
    
    var sourceIsReadable: Bool {
        return FileManager.default.isReadableFile(atPath: sourcePath)
    }
    
    func getSourceInfo() -> (fileCount: Int, totalSize: Int64)? {
        guard !sourcePath.isEmpty else { return nil }
        
        let fileManager = FileManager.default
        var fileCount = 0
        var totalSize: Int64 = 0
        
        guard let enumerator = fileManager.enumerator(atPath: sourcePath) else {
            return nil
        }
        
        while let file = enumerator.nextObject() as? String {
            let fullPath = "\(sourcePath)/\(file)"
            if let attributes = try? fileManager.attributesOfItem(atPath: fullPath),
               let fileType = attributes[.type] as? FileAttributeType,
               fileType == .typeRegular {
                fileCount += 1
                if let size = attributes[.size] as? Int64 {
                    totalSize += size
                }
            }
        }
        
        return (fileCount, totalSize)
    }
    
    var excludeArray: [String] {
        return excludePatterns
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
    
    // MARK: - Password Management (Kept for WebDAV future use)
    
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
    
    // MARK: - URL Construction (Kept for WebDAV future use)
    
    var fullWebDAVURL: String {
        let scheme = webdavUseHTTPS ? "https" : "http"
        let port = serverPort != (webdavUseHTTPS ? 443 : 80) ? ":\(serverPort)" : ""
        let cleanURL = webdavURL.hasPrefix("/") ? webdavURL : "/\(webdavURL)"
        
        return "\(scheme)://\(serverHost)\(port)\(cleanURL)"
    }
    
    var fullWebDAVURLWithPath: String {
        let baseURL = fullWebDAVURL
        let cleanPath = webdavPath.hasPrefix("/") ? webdavPath : "/\(webdavPath)"
        return baseURL + cleanPath
    }
    
    // MARK: - Local Path Construction (Kept for backward compatibility)
    
    var fullLocalDestinationPath: String {
        switch remoteType {
        case .local:
            return localDestinationPath.hasSuffix("/") ?
                String(localDestinationPath.dropLast()) :
                localDestinationPath
        default:
            return localDestinationPath
        }
    }
    
    // MARK: - rclone Configuration (Kept for WebDAV future use)
    
    func generateRcloneConfig() -> String {
        switch remoteType {
        case .webdav:
            return generateWebDAVConfig()
        case .local:
            return generateLocalConfig()
        case .s3, .sftp, .ftp:
            return generatePlaceholderConfig()
        }
    }
    
    private func generateWebDAVConfig() -> String {
        var config = """
        [\(remoteName)]
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
    
    private func generateLocalConfig() -> String {
        return """
        [\(remoteName)]
        type = local
        """
    }
    
    private func generatePlaceholderConfig() -> String {
        return """
        [\(remoteName)]
        type = \(remoteType.rawValue)
        # Configuration for \(remoteType.displayName) not yet implemented
        """
    }
    
    // MARK: - Validation (Kept for backward compatibility and migration)
    
    func validateConfiguration() -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        
        // Note: Most validation should now be done at the profile level
        // This is kept for backward compatibility
        
        if sourcePath.isEmpty {
            errors.append("Source path is required (use profiles instead)")
        } else if !sourceExists {
            errors.append("Source path does not exist: \(sourcePath)")
        } else if !sourceIsReadable {
            errors.append("Source path is not readable: \(sourcePath)")
        }
        
        switch remoteType {
        case .local:
            if localDestinationPath.isEmpty {
                errors.append("Local destination path is required (use profiles instead)")
            }
            
            let fileManager = FileManager.default
            var isDirectory: ObjCBool = false
            
            if !fileManager.fileExists(atPath: localDestinationPath, isDirectory: &isDirectory) {
                errors.append("Local destination path does not exist")
            } else if !isDirectory.boolValue {
                errors.append("Local destination path is not a directory")
            } else {
                if !fileManager.isWritableFile(atPath: localDestinationPath) {
                    errors.append("Local destination path is not writable")
                }
            }
            
            if sourcePath == localDestinationPath {
                errors.append("Source and destination paths cannot be the same")
            }
            
        case .webdav:
            if serverHost.isEmpty {
                errors.append("Server host is required for WebDAV")
            }
            if webdavUsername.isEmpty {
                errors.append("WebDAV username is required")
            }
            if webdavPasswordObscured.isEmpty {
                errors.append("WebDAV password is required")
            }
            
        default:
            errors.append("\(remoteType.displayName) is not yet implemented")
        }
        
        if remoteName.isEmpty {
            errors.append("Remote name is required")
        }
        
        return (errors.isEmpty, errors)
    }
}
