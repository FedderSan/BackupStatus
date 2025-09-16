//
//  LoginItemErrorEnum.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 11/09/2025.
//

enum LoginItemError: Error {
    case failedToEnable
    case failedToDisable
    
    var localizedDescription: String {
        switch self {
        case .failedToEnable:
            return "Failed to enable launch at login"
        case .failedToDisable:
            return "Failed to disable launch at login"
        }
    }
}
