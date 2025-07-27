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
    
    init() {
        self.id = UUID()
        self.serverHost = "MiniServer-DF"
        self.serverPort = 8081
        self.backupIntervalHours = 24 // Once per day
        self.maxRetries = 3
        self.retryDelay = 30
    }
}
