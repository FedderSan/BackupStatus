//
//  BackupManager+TestFunc.swift
//  BackupStatus
//
//  FIXED VERSION: Enhanced connection testing with clear per-profile results
//

import Foundation

extension BackupManager {
    
    // MARK: - Connection Test (ENHANCED - Profile-Based with Clear Results)
    
    func testConnection() async -> Bool {
        logManager.log("", level: .info)
        logManager.log("╔═══════════════════════════════════════════════════════╗", level: .info)
        logManager.log("║    TESTING CONNECTION FOR ALL ENABLED PROFILES        ║", level: .info)
        logManager.log("╚═══════════════════════════════════════════════════════╝", level: .info)
        
        let profiles = await getEnabledProfiles()
        
        guard !profiles.isEmpty else {
            logManager.log("❌ No enabled profiles to test", level: .error)
            logManager.log("💡 Create and enable profiles in the Profiles window", level: .info)
            return false
        }
        
        logManager.log("📋 Found \(profiles.count) enabled profile(s) to test", level: .info)
        logManager.log("", level: .info)
        
        var testResults: [(profile: String, passed: Bool, message: String)] = []
        var allTestsPassed = true
        
        for (index, profile) in profiles.enumerated() {
            logManager.log("┌─────────────────────────────────────────────────────┐", level: .info)
            logManager.log("│ TESTING PROFILE \(index + 1)/\(profiles.count): \(profile.name)", level: .info)
            logManager.log("├─────────────────────────────────────────────────────┤", level: .info)
            logManager.log("│ 📍 Source:      \(profile.sourcePath)", level: .info)
            logManager.log("│ 🎯 Destination: \(profile.destinationPath)", level: .info)
            logManager.log("│ 🌐 Type:        \(profile.remoteType.displayName)", level: .info)
            logManager.log("└─────────────────────────────────────────────────────┘", level: .info)
            
            let validation = profile.validateConfiguration()
            guard validation.isValid else {
                let errorMsg = "Configuration invalid: \(validation.errors.joined(separator: ", "))"
                logManager.log("❌ \(errorMsg)", level: .error)
                testResults.append((profile.name, false, errorMsg))
                allTestsPassed = false
                logManager.log("", level: .info)
                continue
            }
            
            let testPassed: Bool
            let testMessage: String
            
            switch profile.remoteType {
            case .local:
                let result = await testLocalConnectionForProfile(profile)
                testPassed = result.0
                testMessage = result.1
            case .webdav:
                let result = await testWebDAVConnectionForProfile(profile)
                testPassed = result.0
                testMessage = result.1
            }
            
            testResults.append((profile.name, testPassed, testMessage))
            
            if testPassed {
                logManager.log("✅ Profile '\(profile.name)' connection test PASSED", level: .info)
            } else {
                logManager.log("❌ Profile '\(profile.name)' connection test FAILED: \(testMessage)", level: .error)
                allTestsPassed = false
            }
            
            logManager.log("", level: .info)
        }
        
        // Summary
        logManager.log("╔═══════════════════════════════════════════════════════╗", level: .info)
        logManager.log("║    CONNECTION TEST SUMMARY                            ║", level: .info)
        logManager.log("╚═══════════════════════════════════════════════════════╝", level: .info)
        
        for result in testResults {
            let icon = result.passed ? "✅" : "❌"
            let status = result.passed ? "PASSED" : "FAILED"
            logManager.log("\(icon) \(result.profile): \(status)", level: result.passed ? .info : .error)
            if !result.passed {
                logManager.log("   └─ \(result.message)", level: .error)
            }
        }
        
        let passedCount = testResults.filter { $0.passed }.count
        logManager.log("", level: .info)
        logManager.log("📊 Results: \(passedCount)/\(testResults.count) profiles passed", level: allTestsPassed ? .info : .warning)
        
        if allTestsPassed {
            logManager.log("🎉 All connection tests passed!", level: .info)
        } else {
            logManager.log("⚠️ Some connection tests failed. Check the details above.", level: .warning)
        }
        
        return allTestsPassed
    }
    
    // MARK: - Profile-Specific Connection Tests (Enhanced with return messages)
    
    private func testLocalConnectionForProfile(_ profile: BackupProfile) async -> (Bool, String) {
        let fileManager = FileManager.default
        
        // Test source path
        var isSourceDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: profile.sourcePath, isDirectory: &isSourceDirectory),
              isSourceDirectory.boolValue else {
            return (false, "Source path does not exist or is not a directory")
        }
        
        guard fileManager.isReadableFile(atPath: profile.sourcePath) else {
            return (false, "Source path is not readable")
        }
        
        logManager.log("   ✅ Source path OK", level: .debug)
        
        // Test destination path
        var isDestDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: profile.destinationPath, isDirectory: &isDestDirectory),
              isDestDirectory.boolValue else {
            return (false, "Destination path does not exist or is not a directory")
        }
        
        guard fileManager.isWritableFile(atPath: profile.destinationPath) else {
            return (false, "Destination path is not writable")
        }
        
        logManager.log("   ✅ Destination path OK", level: .debug)
        
        // Test creating a temporary file
        let testFileName = UUID().uuidString
        let testFilePath = "\(profile.destinationPath)/.\(testFileName).test"
        
        do {
            try "test".write(toFile: testFilePath, atomically: true, encoding: .utf8)
            try fileManager.removeItem(atPath: testFilePath)
            logManager.log("   ✅ Write test successful", level: .debug)
            return (true, "All tests passed")
        } catch {
            return (false, "Write test failed: \(error.localizedDescription)")
        }
    }
    
    private func testWebDAVConnectionForProfile(_ profile: BackupProfile) async -> (Bool, String) {
        logManager.log("   🔍 Testing WebDAV connection...", level: .debug)
        
        // Test 1: Basic network connectivity
        let networkReachable = await testNetworkReachability(profile.webdavServerHost)
        guard networkReachable else {
            return (false, "Network unreachable: \(profile.webdavServerHost)")
        }
        
        logManager.log("   ✅ Network reachable", level: .debug)
        
        // Test 2: WebDAV authentication and access
        guard let plainPassword = await profile.getPlainPassword() else {
            return (false, "Failed to retrieve password")
        }
        
        let webdavTest = await testWebDAVURL(
            profile.fullWebDAVURL,
            username: profile.webdavUsername,
            password: plainPassword,
            verifySSL: profile.webdavVerifySSL
        )
        
        if webdavTest {
            logManager.log("   ✅ WebDAV connection successful", level: .debug)
            return (true, "All tests passed")
        } else {
            return (false, "WebDAV connection failed - check credentials and URL")
        }
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
