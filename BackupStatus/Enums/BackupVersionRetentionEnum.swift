//
//  BackupVersionRetentionEnum.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 23/09/2025.
//

import Foundation

// MARK: - Backup Version Retention Options
enum BackupVersionRetention: Int, CaseIterable, Codable {
    case versions7 = 7
    case versions14 = 14
    case versions30 = 30
    case versions60 = 60
    case unlimited = -1  // -1 indicates unlimited retention
    
    var displayName: String {
        switch self {
        case .versions7: return "7 versions"
        case .versions14: return "14 versions"
        case .versions30: return "30 versions"
        case .versions60: return "60 versions"
        case .unlimited: return "Unlimited"
        }
    }
    
    var description: String {
        switch self {
        case .versions7: return "Keep last 7 backup versions"
        case .versions14: return "Keep last 14 backup versions"
        case .versions30: return "Keep last 30 backup versions"
        case .versions60: return "Keep last 60 backup versions"
        case .unlimited: return "Keep all backup versions (no cleanup)"
        }
    }
    
    var shouldCleanup: Bool {
        return self != .unlimited
    }
}
