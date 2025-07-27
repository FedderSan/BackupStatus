//
//  BackupSessionModel.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 26/07/2025.
//
import SwiftData
import Foundation

@Model
class BackupSession {
    var id: UUID
    var startTime: Date
    var endTime: Date?
    var status: BackupStatus
    var errorMessage: String?
    var filesBackedUp: Int
    var totalSize: Int64
    
    init(startTime: Date = Date()) {
        self.id = UUID()
        self.startTime = startTime
        self.status = .running
        self.filesBackedUp = 0
        self.totalSize = 0
    }
}
