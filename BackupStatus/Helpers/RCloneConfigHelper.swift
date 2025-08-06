import Foundation

class RcloneConfigHelper {
    static let shared = RcloneConfigHelper()
    
    private init() {}
    
    func generateRemoteConfig(with settings: BackupSettings) -> String {
        switch settings.remoteType {
        case .webdav:
            return generateWebDAVConfig(with: settings)
        case .s3:
            return generateS3Config(with: settings)
        case .sftp:
            return generateSFTPConfig(with: settings)
        case .ftp:
            return generateFTPConfig(with: settings)
        }
    }
    
    private func generateWebDAVConfig(with settings: BackupSettings) -> String {
        var config = """
        [\(settings.remoteName)]
        type = webdav
        url = \(settings.fullWebDAVURL)
        vendor = nextcloud
        user = \(settings.webdavUsername)
        pass = \(settings.webdavPasswordObscured)
        """
        
        // Add SSL verification setting if needed
        if !settings.webdavVerifySSL || !settings.webdavUseHTTPS {
            config += "\ninsecure_skip_verify = true"
        }
        
        return config
    }
    
    private func generateS3Config(with settings: BackupSettings) -> String {
        // Placeholder for S3 configuration
        return """
        [\(settings.remoteName)]
        type = s3
        # S3 configuration would go here
        """
    }
    
    private func generateSFTPConfig(with settings: BackupSettings) -> String {
        // Placeholder for SFTP configuration
        return """
        [\(settings.remoteName)]
        type = sftp
        # SFTP configuration would go here
        """
    }
    
    private func generateFTPConfig(with settings: BackupSettings) -> String {
        // Placeholder for FTP configuration
        return """
        [\(settings.remoteName)]
        type = ftp
        # FTP configuration would go here
        """
    }
    
    func updateConfiguration(with settings: BackupSettings) throws {
        let configPath = "/Users/danielfeddersen/.config/rclone/rclone.conf"
        let configContent = generateRemoteConfig(with: settings)
        
        // Ensure the config directory exists
        let configDir = URL(fileURLWithPath: configPath).deletingLastPathComponent()
        try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        
        // Check if config file exists and read existing content
        var fullConfigContent = ""
        
        if FileManager.default.fileExists(atPath: configPath) {
            let existingContent = try String(contentsOfFile: configPath, encoding: .utf8)
            fullConfigContent = updateExistingConfig(existingContent, with: configContent, remoteName: settings.remoteName)
        } else {
            fullConfigContent = configContent
        }
        
        // Write the updated configuration
        try fullConfigContent.write(toFile: configPath, atomically: true, encoding: .utf8)
    }
    
    private func updateExistingConfig(_ existingContent: String, with newConfig: String, remoteName: String) -> String {
        let lines = existingContent.components(separatedBy: .newlines)
        var updatedLines: [String] = []
        var skipUntilNextSection = false
        
        for line in lines {
            let trimmedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Check if this is a section header
            if trimmedLine.hasPrefix("[") && trimmedLine.hasSuffix("]") {
                let sectionName = String(trimmedLine.dropFirst().dropLast())
                
                if sectionName == remoteName {
                    // We found our target section, skip it entirely
                    skipUntilNextSection = true
                    continue
                } else {
                    // Different section, stop skipping
                    skipUntilNextSection = false
                }
            }
            
            // If we're not skipping, add the line
            if !skipUntilNextSection {
                updatedLines.append(line)
            }
        }
        
        // Add our new configuration at the end
        if !updatedLines.isEmpty && !updatedLines.last!.isEmpty {
            updatedLines.append("") // Add empty line before new section
        }
        updatedLines.append(newConfig)
        
        return updatedLines.joined(separator: "\n")
    }
}
