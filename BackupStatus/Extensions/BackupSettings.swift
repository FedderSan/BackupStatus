//
//  BackupSetting.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 29/07/2025.
//

// MARK: - BackupSettings Extension

extension BackupSettings {
    
    func updateRcloneConfig() throws {
        try RcloneConfigHelper.shared.updateConfiguration(with: self)
    }
}
