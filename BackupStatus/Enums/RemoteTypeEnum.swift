//
//  RemoteTypeEnum.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 29/07/2025.
//

enum RemoteType: String, CaseIterable, Codable {
    case webdav = "webdav"
    case local = "local"
    case s3 = "s3"
    case sftp = "sftp"
    case ftp = "ftp"
    
    var displayName: String {
        switch self {
        case .webdav:
            return "WebDAV (NextCloud/OwnCloud)"
        case .local:
            return "Local/Network Drive"
        case .s3:
            return "Amazon S3"
        case .sftp:
            return "SFTP"
        case .ftp:
            return "FTP"
        }
    }
    
    var requiresNetworkConfig: Bool {
        switch self {
        case .local:
            return false
        default:
            return true
        }
    }
    
    var icon: String {
        switch self {
        case .webdav:
            return "icloud"
        case .local:
            return "externaldrive"
        case .s3:
            return "cube.box"
        case .sftp:
            return "terminal"
        case .ftp:
            return "folder.badge.gearshape"
        }
    }
}
