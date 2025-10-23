//
//  BackupManager+Rsync.swift
//  BackupStatus
//
//  Rsync detection and validation
//

import Foundation

extension BackupManager {
    
    // MARK: - Rsync Path Detection
    
    /// Finds the real GNU rsync (not macOS openrsync)
    var realRsyncPath: String? {
        // Common installation paths for GNU rsync from Homebrew
        let possiblePaths = [
            "/opt/homebrew/bin/rsync",  // Apple Silicon Homebrew
            "/usr/local/bin/rsync",      // Intel Homebrew
        ]
        
        // Check Homebrew paths first (GNU rsync)
        for path in possiblePaths {
            if FileManager.default.fileExists(atPath: path) {
                if isGNURsync(at: path) {
                    logManager.log("✅ Found GNU rsync at: \(path)", level: .debug)
                    return path
                }
            }
        }
        
        // Check system path (/usr/bin/rsync)
        // This is usually openrsync on macOS, so verify it
        let systemPath = "/usr/bin/rsync"
        if FileManager.default.fileExists(atPath: systemPath) {
            if isGNURsync(at: systemPath) {
                logManager.log("✅ Found GNU rsync at: \(systemPath)", level: .debug)
                return systemPath
            } else {
                logManager.log("⚠️ Found openrsync at \(systemPath) (not compatible)", level: .debug)
                return nil  // Explicitly return nil for openrsync
            }
        }
        
        logManager.log("❌ No GNU rsync found", level: .debug)
        return nil
    }
    
    /// Check if we have a real GNU rsync available
    var hasRealRsync: Bool {
        return realRsyncPath != nil
    }
    
    // MARK: - Rsync Validation
    
    /// Verifies if the rsync at the given path is GNU rsync (not openrsync)
    private func isGNURsync(at path: String) -> Bool {
        guard let version = getRsyncVersion(at: path) else {
            return false
        }
        
        // GNU rsync includes "protocol version" in its version output
        // openrsync has "openrsync:" prefix
        let isGNU = version.contains("protocol version") && !version.contains("openrsync")
        
        if isGNU {
            logManager.log("✅ Verified GNU rsync: \(version)", level: .debug)
        } else {
            logManager.log("⚠️ Not GNU rsync: \(version)", level: .debug)
        }
        
        return isGNU
    }
    
    /// Gets the rsync version string
    func getRsyncVersion(at path: String? = nil) -> String? {
        let rsyncPath = path ?? realRsyncPath ?? "/usr/bin/rsync"
        
        guard FileManager.default.fileExists(atPath: rsyncPath) else {
            return nil
        }
        
        let task = Process()
        task.executableURL = URL(fileURLWithPath: rsyncPath)
        task.arguments = ["--version"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            if task.terminationStatus == 0 {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    // Return first line which contains version info
                    return output.components(separatedBy: "\n").first?.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
        } catch {
            logManager.log("Failed to get rsync version: \(error)", level: .debug)
        }
        
        return nil
    }
}
