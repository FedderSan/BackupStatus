//
//  BackupError.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 29/07/2025.
//
// MARK: - Backup Error Types

enum BackupError: Error {
    case sessionNotFound
    case connectionFailed
    case backupFailed(String)
}
