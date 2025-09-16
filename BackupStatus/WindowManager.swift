//
//  WindowManager.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 16/09/2025.
//

// Add this extension to help with safe window management
// Create a new file: WindowManager.swift

import SwiftUI
import AppKit

@MainActor
class WindowManager: ObservableObject {
    static let shared = WindowManager()
    
    private init() {}
    
    func openWindow(_ identifier: String) {
        // Add a small delay to prevent ViewBridge issues
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000) // 0.05 seconds
            
            if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == identifier }) {
                // Window already exists, just bring it to front
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            } else {
                // Open new window
                NSApp.sendAction(Selector(("showWindow")), to: nil, from: identifier)
            }
        }
    }
    
    func closeWindow(_ identifier: String) {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue == identifier }) {
            window.close()
        }
    }
}
