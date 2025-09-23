//
//  LogRetentionPeriodEnum.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 18/09/2025.
//
import Foundation
// MARK: - Log Retention Options
enum LogRetentionPeriod: Int, CaseIterable, Codable {
    case days14 = 14
    case days30 = 30
    case days60 = 60
    case days90 = 90
    
    var displayName: String {
        switch self {
        case .days14: return "14 days"
        case .days30: return "30 days"
        case .days60: return "60 days"
        case .days90: return "90 days"
        }
    }
    
    var cutoffDate: Date {
        Calendar.current.date(byAdding: .day, value: -self.rawValue, to: Date()) ?? Date()
    }
}
