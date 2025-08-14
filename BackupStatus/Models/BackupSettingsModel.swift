import SwiftData
import Foundation

@Model
class BackupSettings {
    var id: UUID
    var serverHost: String
    var serverPort: Int
    var backupIntervalHours: Int
    var lastSuccessfulBackup: Date?
    
    // Source Configuration (NEW)
    var sourcePath: String
    var excludePatterns: String  // Comma-separated patterns to exclude
    
    // WebDAV Configuration
    var webdavEnabled: Bool
    var webdavURL: String  // Path part only: "/remote.php/dav/files/daniel"
    var webdavUsername: String
    var webdavPasswordObscured: String
    var webdavPath: String  // Backup folder: "/BackupFolderLaptop"
    var webdavUseHTTPS: Bool
    var webdavVerifySSL: Bool
    
    // Local/Network Drive Configuration
    var localDestinationPath: String  // e.g., "/Users/df/filen/backups"
    var localCreateDatedFolders: Bool  // Whether to create dated subfolders
    
    // Remote Configuration
    var remoteName: String
    var remoteType: RemoteType
    
    init() {
        self.id = UUID()
        self.serverHost = "MiniServer-DF"
        self.serverPort = 8081
        self.backupIntervalHours = 24
        
        // Source defaults (NEW)
        self.sourcePath = "/Users/danielfeddersen/Library/CloudStorage/OneDrive-Personal/workOnedrive"
        self.excludePatterns = ".DS_Store,*.tmp,*.cache"
        
        // WebDAV defaults
        self.webdavEnabled = true
        self.webdavURL = "/remote.php/dav/files/daniel"
        self.webdavUsername = "danielfeddersen@gmail.com"
        self.webdavPasswordObscured = ""
        self.webdavPath = "/BackupFolderLaptop"
        self.webdavUseHTTPS = false
        self.webdavVerifySSL = true
        
        // Local defaults
        self.localDestinationPath = "/Users/danielfeddersen/Library/Mobile Documents/com~apple~CloudDocs/BackupOneDrive"
        self.localCreateDatedFolders = true
        
        // Remote defaults
        self.remoteName = "backup-remote"
        self.remoteType = .local  // Default to local now
    }
    
    // MARK: - Source Path Helpers (NEW)
    
    var fullSourcePath: String {
        // Ensure path ends with trailing slash for rsync/rclone
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
    
    // MARK: - Password Management
    
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
    
    // MARK: - URL Construction
    
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
    
    // MARK: - Local Path Construction
    
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
    
    func localLatestPath() -> String {
        let basePath = fullLocalDestinationPath
        return "\(basePath)/latest"
    }
    
    func localVersionPath(for date: Date = Date()) -> String {
        let basePath = fullLocalDestinationPath
        
        if localCreateDatedFolders {
            let dateFormatter = DateFormatter()
            dateFormatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
            let dateString = dateFormatter.string(from: date)
            return "\(basePath)/versions/\(dateString)"
        } else {
            // If versioning is disabled, only update latest
            return localLatestPath()
        }
    }
    
    // MARK: - rclone Configuration
    
    func generateRcloneConfig() -> String {
        switch remoteType {
        case .webdav:
            return generateWebDAVConfig()
        case .local:
            return generateLocalConfig()
        case .s3, .sftp, .ftp:
            // Placeholder for future implementations
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
    
    // MARK: - Validation
    
    func validateConfiguration() -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        
        // Validate source path (NEW)
        if sourcePath.isEmpty {
            errors.append("Source path is required")
        } else if !sourceExists {
            errors.append("Source path does not exist: \(sourcePath)")
        } else if !sourceIsReadable {
            errors.append("Source path is not readable: \(sourcePath)")
        }
        
        switch remoteType {
        case .local:
            if localDestinationPath.isEmpty {
                errors.append("Local destination path is required")
            }
            
            // Check if path exists and is writable
            let fileManager = FileManager.default
            var isDirectory: ObjCBool = false
            
            if !fileManager.fileExists(atPath: localDestinationPath, isDirectory: &isDirectory) {
                errors.append("Local destination path does not exist")
            } else if !isDirectory.boolValue {
                errors.append("Local destination path is not a directory")
            } else {
                // Check if writable
                if !fileManager.isWritableFile(atPath: localDestinationPath) {
                    errors.append("Local destination path is not writable")
                }
            }
            
            // Check that source and destination are different
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
