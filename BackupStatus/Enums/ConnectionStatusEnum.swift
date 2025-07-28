//
//  ConnectionStatusEnum.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 28/07/2025.
//

// Add this enum to your project (could be in a separate file or added to existing model files)
import SwiftUI

enum ConnectionStatus: String, CaseIterable {
    case unknown = "unknown"
    case testing = "testing"
    case connected = "connected"
    case failed = "failed"
    
    var displayName: String {
        switch self {
        case .unknown:
            return "Unknown"
        case .testing:
            return "Testing..."
        case .connected:
            return "Connected"
        case .failed:
            return "Failed"
        }
    }
    
    var systemImage: String {
        switch self {
        case .unknown:
            return "questionmark.circle"
        case .testing:
            return "circle.dotted"
        case .connected:
            return "checkmark.circle.fill"
        case .failed:
            return "xmark.circle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .unknown:
            return .gray
        case .testing:
            return .orange
        case .connected:
            return .green
        case .failed:
            return .red
        }
    }
}
