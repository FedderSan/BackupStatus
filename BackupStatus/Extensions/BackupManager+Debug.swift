//
//  BackupManager+Debug.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 21/10/2025.
//

import Foundation

extension BackupManager {
    
    // MARK: - Debug Methods (Always available - controlled by UI)
    
    func debugConnection() async -> Bool {
        guard let settings = await dataActor.getSettings() else {
            logManager.log("❌ No settings found for debug", level: .error)
            return false
        }
        
        logManager.log("📁 Source: \(settings.fullSourcePath)", level: .debug)
        logManager.log("📁 Source exists: \(settings.sourceExists)", level: .debug)
        logManager.log("📁 Source readable: \(settings.sourceIsReadable)", level: .debug)
        logManager.log("🔧 rclone path: \(rclonePath)", level: .debug)
        logManager.log("📋 Config path: \(configPath)", level: .debug)
        
        switch settings.remoteType {
        case .local:
            logManager.log("📁 Destination: \(settings.fullLocalDestinationPath)", level: .debug)
            return await testLocalConnection(settings)
        case .webdav:
            return await ConnectionDebugHelper.shared.debugConnection(with: settings, logManager: logManager)
        default:
            logManager.log("❌ Debug not implemented for \(settings.remoteType.displayName)", level: .error)
            return false
        }
    }
    
    func debugRcloneConfig() async {
        guard let settings = await dataActor.getSettings() else {
            logManager.log("❌ No settings found", level: .error)
            return
        }
        
        logManager.log("🔧 Current configuration:", level: .info)
        logManager.log("Remote Type: \(settings.remoteType.displayName)", level: .debug)
        logManager.log("Source Path: \(settings.fullSourcePath)", level: .debug)
        logManager.log("rclone Path: \(rclonePath)", level: .debug)
        logManager.log("Config Path: \(configPath)", level: .debug)
        
        if let sourceInfo = settings.getSourceInfo() {
            logManager.log("Source contains: \(sourceInfo.fileCount) files, \(ByteCountFormatter.string(fromByteCount: sourceInfo.totalSize, countStyle: .file))", level: .debug)
        }
        
        switch settings.remoteType {
        case .local:
            logManager.log("Local Path: \(settings.localDestinationPath)", level: .debug)
            logManager.log("Create Dated Folders: \(settings.localCreateDatedFolders)", level: .debug)
            logManager.log("Latest Path: \(settings.localLatestPath())", level: .debug)
            logManager.log("Version Path: \(settings.localVersionPath())", level: .debug)
        case .webdav:
            let config = settings.generateRcloneConfig()
            logManager.log(config, level: .debug)
        default:
            logManager.log("Configuration not yet implemented for \(settings.remoteType.displayName)", level: .debug)
        }
        
        if !settings.excludePatterns.isEmpty {
            logManager.log("Exclude patterns: \(settings.excludeArray.joined(separator: ", "))", level: .debug)
        }
    }
    func debugPasswordHandling() async {
        guard let settings = await dataActor.getSettings() else {
            logManager.log("❌ No settings found", level: .error)
            return
        }
        
        switch settings.remoteType {
        case .webdav:
            logManager.log("🔐 Testing WebDAV password handling:", level: .info)
            logManager.log("Obscured password: \(settings.webdavPasswordObscured.isEmpty ? "EMPTY" : "SET")", level: .debug)
            
            if let plainPassword = await settings.getPlainPassword() {
                logManager.log("✅ Password reveal successful (length: \(plainPassword.count))", level: .debug)
            } else {
                logManager.log("❌ Password reveal failed", level: .error)
            }
        case .local:
            logManager.log("🔐 Local backup doesn't require password authentication", level: .info)
        default:
            logManager.log("🔐 Password handling not implemented for \(settings.remoteType.displayName)", level: .info)
        }
    }
}
