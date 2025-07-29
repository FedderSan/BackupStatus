//
//  BackupSetting.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 29/07/2025.
//

// MARK: - BackupSettings Extension

extension BackupSettings {
    func generateRcloneConfig() -> String {
        return RcloneConfigHelper.shared.generateRemoteConfig(with: self)
    }
    
    func updateRcloneConfig() throws {
        try RcloneConfigHelper.shared.updateConfiguration(with: self)
    }
}
