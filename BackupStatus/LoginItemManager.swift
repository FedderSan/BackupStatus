//
//  LoginItemManager.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 11/09/2025.
//

import Foundation
import ServiceManagement

class LoginItemManager {
    static let shared = LoginItemManager()
    
    private init() {}
    
    // Check if the app is set to launch at login
    var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        } else {
            // For older macOS versions, check login items manually
            return isInLoginItems()
        }
    }
    
    // Enable or disable launch at login
    func setEnabled(_ enabled: Bool) throws {
        if #available(macOS 13.0, *) {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } else {
            // For older macOS versions
            try setLoginItemEnabled(enabled)
        }
    }
    
    // MARK: - Legacy Methods (macOS 12 and earlier)
    
    private func isInLoginItems() -> Bool {
        guard let loginItems = SMCopyAllJobDictionaries(kSMDomainUserLaunchd)?.takeRetainedValue() as? [[String: Any]] else {
            return false
        }
        
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
        
        return loginItems.contains { item in
            (item["Label"] as? String) == bundleIdentifier
        }
    }
    
    private func setLoginItemEnabled(_ enabled: Bool) throws {
        let bundleIdentifier = Bundle.main.bundleIdentifier ?? ""
        
        if enabled {
            if !SMLoginItemSetEnabled(bundleIdentifier as CFString, true) {
                throw LoginItemError.failedToEnable
            }
        } else {
            if !SMLoginItemSetEnabled(bundleIdentifier as CFString, false) {
                throw LoginItemError.failedToDisable
            }
        }
    }
}
