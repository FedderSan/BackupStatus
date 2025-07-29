//
//  RemoteTypeEnum.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 29/07/2025.
//

enum RemoteType: String, CaseIterable, Codable {
    case webdav = "webdav"
    case s3 = "s3"
    case sftp = "sftp"
    case ftp = "ftp"
    
    var displayName: String {
        switch self {
        case .webdav:
            return "WebDAV"
        case .s3:
            return "Amazon S3"
        case .sftp:
            return "SFTP"
        case .ftp:
            return "FTP"
        }
    }
}
