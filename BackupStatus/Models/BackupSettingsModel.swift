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
    var webdavPassword: String
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
        self.webdavURL = "http://MiniServer-DF:8081/remote.php/dav/files/daniel"
        self.webdavUsername = "danielfeddersen@gmail.com"
        self.webdavPassword = "6yw94vz2malsy1PIlPIk1w6p_XxL_zdgCzP_FeHWQAbpeg"
        self.webdavPath = "/BackupFolderLaptop"
        self.webdavUseHTTPS = false
        self.webdavVerifySSL = true
        
        // Remote defaults
        self.remoteName = "nextcloud-backup"
        self.remoteType = .webdav
    }
    
    // Computed property for full WebDAV URL
    var fullWebDAVURL: String {
        let scheme = webdavUseHTTPS ? "https" : "http"
        let port = serverPort != (webdavUseHTTPS ? 443 : 80) ? ":\(serverPort)" : ""
        return "\(scheme)://\(serverHost)\(port)\(webdavURL)"
    }
    
    // Computed property for generating rclone config path
    var rcloneConfigPath: String {
        return "/Users/danielfeddersen/.config/rclone/rclone.conf"
    }
}

enum RemoteType: String, CaseIterable, Codable {
    case webdav = "webdav"
    case s3 = "s3"
    case sftp = "sftp"
    case ftp = "ftp"
    
    var displayName: String {
        switch self {
        case .webdav:
            return "WebDAV"
        case .s3:
            return "Amazon S3"
        case .sftp:
            return "SFTP"
        case .ftp:
            return "FTP"
        }
    }
}
