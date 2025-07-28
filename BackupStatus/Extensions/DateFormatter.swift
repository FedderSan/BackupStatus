//
//  DateFormatter+Extensions.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 26/07/2025.
//

import Foundation

extension DateFormatter {
    static let dailyFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
    
    static let versionFormat: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        return formatter
    }()
}
