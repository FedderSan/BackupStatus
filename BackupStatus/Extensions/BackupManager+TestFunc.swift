//
//  BackupManager+TestFunc.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 21/10/2025.
//

import Foundation

extension BackupManager {
    
    // MARK: - Connection Test (Profile-Based)
    
    func testConnection() async -> Bool {
        logManager.log("🔍 Testing connection for enabled profiles", level: .info)
        
        let profiles = await getEnabledProfiles()
        
        guard !profiles.isEmpty else {
            logManager.log("❌ No enabled profiles to test", level: .error)
            return false
        }
        
        var allTestsPassed = true
        
        for profile in profiles {
            logManager.log("Testing profile: \(profile.name) (\(profile.remoteType.displayName))", level: .info)
            
            let validation = profile.validateConfiguration()
            guard validation.isValid else {
                logManager.log("❌ Profile '\(profile.name)' configuration invalid: \(validation.errors.joined(separator: ", "))", level: .error)
                allTestsPassed = false
                continue
            }
            
            let testPassed: Bool
            
            switch profile.remoteType {
            case .local:
                testPassed = await testLocalConnectionForProfile(profile)
            case .webdav:
                testPassed = await testWebDAVConnectionForProfile(profile)
            }
            
            if testPassed {
                logManager.log("✅ Profile '\(profile.name)' connection test passed", level: .info)
            } else {
                logManager.log("❌ Profile '\(profile.name)' connection test failed", level: .error)
                allTestsPassed = false
            }
        }
        
        return allTestsPassed
    }
    
    // MARK: - Profile-Specific Connection Tests
    
    private func testLocalConnectionForProfile(_ profile: BackupProfile) async -> Bool {
        let fileManager = FileManager.default
        
        // Test source path
        var isSourceDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: profile.sourcePath, isDirectory: &isSourceDirectory),
              isSourceDirectory.boolValue else {
            logManager.log("❌ Source path does not exist or is not a directory: \(profile.sourcePath)", level: .error)
            return false
        }
        
        guard fileManager.isReadableFile(atPath: profile.sourcePath) else {
            logManager.log("❌ Source path is not readable: \(profile.sourcePath)", level: .error)
            return false
        }
        
        logManager.log("✅ Source path OK: \(profile.sourcePath)", level: .debug)
        
        // Test destination path
        var isDestDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: profile.destinationPath, isDirectory: &isDestDirectory),
              isDestDirectory.boolValue else {
            logManager.log("❌ Destination path does not exist or is not a directory: \(profile.destinationPath)", level: .error)
            return false
        }
        
        guard fileManager.isWritableFile(atPath: profile.destinationPath) else {
            logManager.log("❌ Destination path is not writable: \(profile.destinationPath)", level: .error)
            return false
        }
        
        logManager.log("✅ Destination path OK: \(profile.destinationPath)", level: .debug)
        
        // Test creating a temporary file
        let testFileName = UUID().uuidString
        let testFilePath = "\(profile.destinationPath)/.\(testFileName).test"
        
        do {
            try "test".write(toFile: testFilePath, atomically: true, encoding: .utf8)
            try fileManager.removeItem(atPath: testFilePath)
            logManager.log("✅ Write test successful", level: .debug)
            return true
        } catch {
            logManager.log("❌ Write test failed: \(error)", level: .error)
            return false
        }
    }
    
    private func testWebDAVConnectionForProfile(_ profile: BackupProfile) async -> Bool {
        logManager.log("Testing WebDAV connection for profile: \(profile.name)", level: .debug)
        
        // Test 1: Basic network connectivity
        guard await testNetworkReachability(profile.webdavServerHost) else {
            logManager.log("❌ Network unreachable: \(profile.webdavServerHost)", level: .error)
            return false
        }
        
        logManager.log("✅ Network reachable", level: .debug)
        
        // Test 2: WebDAV authentication and access
        guard let plainPassword = await profile.getPlainPassword() else {
            logManager.log("❌ Failed to retrieve password", level: .error)
            return false
        }
        
        let webdavTest = await testWebDAVURL(
            profile.fullWebDAVURL,
            username: profile.webdavUsername,
            password: plainPassword,
            verifySSL: profile.webdavVerifySSL
        )
        
        if webdavTest {
            logManager.log("✅ WebDAV connection successful", level: .info)
        } else {
            logManager.log("❌ WebDAV connection failed", level: .error)
        }
        
        return webdavTest
    }
    
    // MARK: - Low-Level Test Functions
    
    func testNetworkReachability(_ host: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/sbin/ping")
            task.arguments = ["-c", "1", "-W", "5000", host]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                continuation.resume(returning: task.terminationStatus == 0)
            } catch {
                logManager.log("❌ Ping failed: \(error)", level: .error)
                continuation.resume(returning: false)
            }
        }
    }
    
    func testWebDAVURL(_ url: String, username: String, password: String, verifySSL: Bool) async -> Bool {
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            
            var arguments = [
                "-s", "-f", "-X", "PROPFIND",
                "--user", "\(username):\(password)",
                "-H", "Content-Type: text/xml",
                "-H", "Depth: 0",
                "--max-time", "10"
            ]
            
            if !verifySSL {
                arguments.append("-k")
            }
            
            arguments.append(url)
            task.arguments = arguments
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                if task.terminationStatus != 0 {
                    let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    logManager.log("❌ WebDAV test output: \(errorOutput)", level: .error)
                }
                
                continuation.resume(returning: task.terminationStatus == 0)
            } catch {
                logManager.log("❌ WebDAV test error: \(error)", level: .error)
                continuation.resume(returning: false)
            }
        }
    }
    
    // MARK: - Legacy Test Functions (Deprecated - kept for backward compatibility)
    
    @available(*, deprecated, message: "Use testConnection() instead, which tests all enabled profiles")
    func testLocalConnection(_ settings: BackupSettings) async -> Bool {
        logManager.log("⚠️ Using deprecated testLocalConnection - consider using profile-based testing", level: .warning)
        
        let fileManager = FileManager.default
        
        // Test source path
        guard settings.sourceExists else {
            logManager.log("Source path does not exist: \(settings.sourcePath)", level: .error)
            return false
        }
        
        guard settings.sourceIsReadable else {
            logManager.log("Source path is not readable: \(settings.sourcePath)", level: .error)
            return false
        }
        
        // Test destination path
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: settings.localDestinationPath, isDirectory: &isDirectory) else {
            logManager.log("Local destination path does not exist: \(settings.localDestinationPath)", level: .error)
            return false
        }
        
        guard isDirectory.boolValue else {
            logManager.log("Local destination path is not a directory: \(settings.localDestinationPath)", level: .error)
            return false
        }
        
        guard fileManager.isWritableFile(atPath: settings.localDestinationPath) else {
            logManager.log("Local destination path is not writable: \(settings.localDestinationPath)", level: .error)
            return false
        }
        
        // Test creating a temporary file
        let testFileName = UUID().uuidString
        let testFilePath = "\(settings.localDestinationPath)/.\(testFileName).test"
        
        do {
            try "test".write(toFile: testFilePath, atomically: true, encoding: .utf8)
            try fileManager.removeItem(atPath: testFilePath)
            logManager.log("Local connection test successful", level: .info)
            return true
        } catch {
            logManager.log("Local connection test failed: \(error)", level: .error)
            return false
        }
    }
}
