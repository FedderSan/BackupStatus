//
//  LogRetentionPeriodEnum.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 18/09/2025.
//
import Foundation

// MARK: - Log Retention Options (UPDATED with additional options)
enum LogRetentionPeriod: Int, CaseIterable, Codable {
    case days7 = 7      // NEW: 1 week
    case days14 = 14    // 2 weeks
    case days30 = 30    // 1 month
    case days60 = 60    // 2 months
    case days90 = 90    // 3 months
    case days180 = 180  // NEW: 6 months
    
    var displayName: String {
        switch self {
        case .days7: return "7 days"
        case .days14: return "14 days"
        case .days30: return "1 month"
        case .days60: return "2 months"
        case .days90: return "3 months"
        case .days180: return "6 months"
        }
    }
    
    var description: String {
        switch self {
        case .days7: return "Keep logs for 1 week"
        case .days14: return "Keep logs for 2 weeks"
        case .days30: return "Keep logs for 1 month"
        case .days60: return "Keep logs for 2 months"
        case .days90: return "Keep logs for 3 months"
        case .days180: return "Keep logs for 6 months"
        }
    }
    
    var cutoffDate: Date {
        Calendar.current.date(byAdding: .day, value: -self.rawValue, to: Date()) ?? Date()
    }
}
