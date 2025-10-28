//
//  ProfileRemoteTypeEnum.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 28/10/2025.
//

//
//  ProfileRemoteTypeEnum.swift
//  BackupStatus
//
//  Profile remote destination types
//

import Foundation

// MARK: - Profile Remote Types
enum ProfileRemoteType: String, Codable, CaseIterable {
    case local = "local"
    case webdav = "webdav"
    
    var displayName: String {
        switch self {
        case .local:
            return "Local/Network Drive"
        case .webdav:
            return "WebDAV (Nextcloud/OwnCloud)"
        }
    }
    
    var description: String {
        switch self {
        case .local:
            return "Backup to a local folder or network drive"
        case .webdav:
            return "Backup to a WebDAV server (Nextcloud, OwnCloud, etc.)"
        }
    }
    
    var icon: String {
        switch self {
        case .local:
            return "externaldrive.fill"
        case .webdav:
            return "cloud.fill"
        }
    }
    
    var requiresNetworkConfig: Bool {
        switch self {
        case .local:
            return false
        case .webdav:
            return true
        }
    }
}
