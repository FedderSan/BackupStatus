import SwiftData
import Foundation

// MARK: - Backup Profile Types
enum BackupProfileType: String, Codable, CaseIterable {
    case versioned = "versioned"
    case oneWaySync = "one_way_sync"
    
    var displayName: String {
        switch self {
        case .versioned:
            return "Versioned Backup"
        case .oneWaySync:
            return "One-Way Sync"
        }
    }
    
    var description: String {
        switch self {
        case .versioned:
            return "Creates timestamped versions and maintains a 'latest' folder"
        case .oneWaySync:
            return "Mirrors source to destination with trash folder for deletions"
        }
    }
    
    var icon: String {
        switch self {
        case .versioned:
            return "clock.arrow.circlepath"
        case .oneWaySync:
            return "arrow.right.circle"
        }
    }
}
