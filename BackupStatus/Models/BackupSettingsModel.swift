//
//  BackupSettingsModel.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 26/07/2025.
//
import SwiftData
import Foundation

@Model
class BackupSettings {
    var id: UUID
    var serverHost: String
    var serverPort: Int
    var backupIntervalHours: Int
    var lastSuccessfulBackup: Date?
    var maxRetries: Int
    var retryDelay: Int
    
    // WebDAV Configuration
    var webdavEnabled: Bool
    var webdavURL: String
    var webdavUsername: String
    var webdavPasswordObscured: String  // Store the obscured password
    var webdavPath: String
    var webdavUseHTTPS: Bool
    var webdavVerifySSL: Bool
    
    // Remote Configuration (for rclone)
    var remoteName: String
    var remoteType: RemoteType
    
    init() {
        self.id = UUID()
        self.serverHost = "MiniServer-DF"
        self.serverPort = 8081
        self.backupIntervalHours = 24 // Once per day
        self.maxRetries = 3
        self.retryDelay = 30
        
        // WebDAV defaults
        self.webdavEnabled = true
        // Store only the path part, not the full URL
        self.webdavURL = "/remote.php/dav/files/daniel"
        self.webdavUsername = "danielfeddersen@gmail.com"
        self.webdavPasswordObscured = "" // Will be set when password is provided
        self.webdavPath = "/BackupFolderLaptop"
        self.webdavUseHTTPS = false
        self.webdavVerifySSL = true
        
        // Remote defaults
        self.remoteName = "nextcloud-backup"
        self.remoteType = .webdav
    }
    
    // MARK: - Password Management Methods
    
    /// Sets the password by obscuring it first
    func setPassword(_ plainPassword: String) async {
        if let obscured = await RclonePasswordHelper.shared.obscurePassword(plainPassword) {
            self.webdavPasswordObscured = obscured
        } else {
            print("Failed to obscure password, storing empty string")
            self.webdavPasswordObscured = ""
        }
    }
    
    /// Gets the plain text password by revealing the obscured one
    func getPlainPassword() async -> String? {
        guard !webdavPasswordObscured.isEmpty else { return nil }
        return await RclonePasswordHelper.shared.revealPassword(webdavPasswordObscured)
    }
    
    /// Gets the obscured password for rclone config
    var obscuredPassword: String {
        return webdavPasswordObscured
    }
    
    // MARK: - Computed Properties
    
    // Fixed: Properly construct the base WebDAV URL without the backup path
    var fullWebDAVURL: String {
        let scheme = webdavUseHTTPS ? "https" : "http"
        let port = serverPort != (webdavUseHTTPS ? 443 : 80) ? ":\(serverPort)" : ""
        
        // Clean webdavURL to ensure it starts with /
        let cleanWebdavURL = webdavURL.hasPrefix("/") ? webdavURL : "/\(webdavURL)"
        
        return "\(scheme)://\(serverHost)\(port)\(cleanWebdavURL)"
    }
    
    // New: Get the complete WebDAV URL including the backup path
    var fullWebDAVURLWithPath: String {
        let baseURL = fullWebDAVURL
        let cleanPath = webdavPath.hasPrefix("/") ? webdavPath : "/\(webdavPath)"
        return baseURL + cleanPath
    }
    
    // Computed property for generating rclone config path
    var rcloneConfigPath: String {
        return "/Users/danielfeddersen/.config/rclone/rclone.conf"
    }
    
    // MARK: - rclone Configuration Generation
    
    func generateRcloneConfig() -> String {
        var config = """
        [\(remoteName)]
        type = webdav
        url = \(fullWebDAVURL)
        vendor = nextcloud
        user = \(webdavUsername)
        pass = \(webdavPasswordObscured)
        """
        
        // Add SSL verification setting if needed
        if !webdavVerifySSL || !webdavUseHTTPS {
            config += "\ninsecure_skip_verify = true"
        }
        
        return config
    }
    
    func updateRcloneConfig() throws {
        let configPath = rcloneConfigPath
        let configContent = generateRcloneConfig()
        
        // Check if config directory exists, create if not
        let configDir = URL(fileURLWithPath: configPath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        
        // Write the configuration
        try configContent.write(toFile: configPath, atomically: true, encoding: .utf8)
        print("Updated rclone configuration at \(configPath)")
    }
}
