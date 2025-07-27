//
//  BackupStatusEnum.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 26/07/2025.
//

enum BackupStatus: String, CaseIterable, Codable {
    case running = "running"
    case success = "success"
    case failed = "failed"
    case connectionError = "connection_error"
    case skipped = "skipped"
}
