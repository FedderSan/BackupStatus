import SwiftData
import Foundation

@Model
class BackupSettings {
    var id: UUID
    var serverHost: String
    var serverPort: Int
    var backupIntervalHours: Int
    var lastSuccessfulBackup: Date?
    
    // WebDAV Configuration
    var webdavEnabled: Bool
    var webdavURL: String  // Path part only: "/remote.php/dav/files/daniel"
    var webdavUsername: String
    var webdavPasswordObscured: String
    var webdavPath: String  // Backup folder: "/BackupFolderLaptop"
    var webdavUseHTTPS: Bool
    var webdavVerifySSL: Bool
    
    // Remote Configuration
    var remoteName: String
    var remoteType: RemoteType
    
    init() {
        self.id = UUID()
        self.serverHost = "MiniServer-DF"
        self.serverPort = 8081
        self.backupIntervalHours = 24
        
        // WebDAV defaults
        self.webdavEnabled = true
        self.webdavURL = "/remote.php/dav/files/daniel"
        self.webdavUsername = "danielfeddersen@gmail.com"
        self.webdavPasswordObscured = ""
        self.webdavPath = "/BackupFolderLaptop"
        self.webdavUseHTTPS = false
        self.webdavVerifySSL = true
        
        // Remote defaults
        self.remoteName = "nextcloud-backup"
        self.remoteType = .webdav
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
    
    // MARK: - rclone Configuration
    
    func generateRcloneConfig() -> String {
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
}
