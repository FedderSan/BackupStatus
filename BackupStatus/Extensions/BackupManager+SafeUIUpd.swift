//
//  BackupManager+SafeUIUpd.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 21/10/2025.
//
import Foundation

extension BackupManager {
    func updateStatus(_ status: BackupStatus, debounce: Bool = true) {
        // Cancel previous update if debouncing
        if debounce {
            statusUpdateTask?.cancel()
        }
        
        statusUpdateTask = Task { @MainActor in
            if debounce {
                // Small delay to prevent rapid updates
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
                if Task.isCancelled { return }
            }
            
            self.currentStatus = status
            self.logManager.updateBackupStatus(status)
        }
    }
}
