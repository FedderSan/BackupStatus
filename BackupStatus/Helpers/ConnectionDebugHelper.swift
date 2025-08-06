//
//  ConnectionDebugHelper.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 06/08/2025.
//

//
//  ConnectionDebugHelper.swift
//  BackupStatus
//
//  Helper for debugging connection issues
//

import Foundation

class ConnectionDebugHelper {
    static let shared = ConnectionDebugHelper()
    
    private init() {}
    
    /// Comprehensive connection test that logs detailed information
    func debugConnection(with settings: BackupSettings, logManager: LogManager) async -> Bool {
        logManager.log("🔍 Starting comprehensive connection debug", level: .info)
        
        // Step 1: Test basic network connectivity
        let networkOK = await testNetworkConnectivity(host: settings.serverHost, port: settings.serverPort, logManager: logManager)
        
        // Step 2: Test WebDAV connection with detailed logging
        let webdavOK = await testWebDAVWithDebug(settings: settings, logManager: logManager)
        
        // Step 3: Test rclone config generation
        let configOK = await testRcloneConfig(settings: settings, logManager: logManager)
        
        // Step 4: Test rclone connection
        let rcloneOK = await testRcloneConnection(settings: settings, logManager: logManager)
        
        let overallSuccess = networkOK && webdavOK && configOK && rcloneOK
        
        logManager.log("🏁 Debug summary: Network=\(networkOK), WebDAV=\(webdavOK), Config=\(configOK), rclone=\(rcloneOK)", level: overallSuccess ? .info : .error)
        
        return overallSuccess
    }
    
    private func testNetworkConnectivity(host: String, port: Int, logManager: LogManager) async -> Bool {
        logManager.log("🌐 Testing network connectivity to \(host):\(port)", level: .debug)
        
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/nc")
            task.arguments = ["-z", "-v", "-w", "5", host, String(port)]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                let success = task.terminationStatus == 0
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                
                if success {
                    logManager.log("✅ Network connectivity OK", level: .debug)
                } else {
                    logManager.log("❌ Network connectivity failed: \(output)", level: .error)
                }
                
                continuation.resume(returning: success)
            } catch {
                logManager.log("❌ Network test error: \(error)", level: .error)
                continuation.resume(returning: false)
            }
        }
    }
    
    private func testWebDAVWithDebug(settings: BackupSettings, logManager: LogManager) async -> Bool {
        // Test both base URL and full URL with path
        let baseURL = settings.fullWebDAVURL
        let fullURL = settings.fullWebDAVURLWithPath
        
        logManager.log("🔗 Testing WebDAV URLs:", level: .debug)
        logManager.log("  Base URL: \(baseURL)", level: .debug)
        logManager.log("  Full URL: \(fullURL)", level: .debug)
        
        guard let plainPassword = await settings.getPlainPassword() else {
            logManager.log("❌ Failed to retrieve plain password", level: .error)
            return false
        }
        
        // Test base URL first
        let baseTest = await testWebDAVURL(baseURL, username: settings.webdavUsername, password: plainPassword, verifySSL: settings.webdavVerifySSL, logManager: logManager)
        
        if !baseTest {
            logManager.log("❌ Base WebDAV URL test failed", level: .error)
            return false
        }
        
        // Test full URL with path
        let pathTest = await testWebDAVURL(fullURL, username: settings.webdavUsername, password: plainPassword, verifySSL: settings.webdavVerifySSL, logManager: logManager)
        
        if pathTest {
            logManager.log("✅ Both WebDAV URLs accessible", level: .debug)
        } else {
            logManager.log("⚠️ Base URL OK, but backup path may not exist", level: .warning)
        }
        
        return baseTest // Return true if base URL works, even if path doesn't exist
    }
    
    private func testWebDAVURL(_ url: String, username: String, password: String, verifySSL: Bool, logManager: LogManager) async -> Bool {
        logManager.log("🔍 Testing WebDAV URL: \(url)", level: .debug)
        
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            
            var arguments = [
                "-v", // Verbose output for debugging
                "-X", "PROPFIND",
                "--user", "\(username):\(password)",
                "-H", "Content-Type: text/xml",
                "-H", "Depth: 0",
                "--max-time", "15"
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
                
                let success = task.terminationStatus == 0
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                
                // Log detailed curl output for debugging
                if !success {
                    logManager.log("❌ Curl output: \(output)", level: .error)
                } else {
                    logManager.log("✅ WebDAV PROPFIND successful", level: .debug)
                }
                
                continuation.resume(returning: success)
            } catch {
                logManager.log("❌ Curl execution error: \(error)", level: .error)
                continuation.resume(returning: false)
            }
        }
    }
    
    private func testRcloneConfig(settings: BackupSettings, logManager: LogManager) async -> Bool {
        logManager.log("⚙️ Testing rclone config generation", level: .debug)
        
        let configContent = settings.generateRcloneConfig()
        logManager.log("Generated config:\n\(configContent)", level: .debug)
        
        // Verify password is obscured
        if settings.webdavPasswordObscured.isEmpty {
            logManager.log("❌ Password is not obscured", level: .error)
            return false
        }
        
        // Try to write config
        do {
            let configPath = settings.rcloneConfigPath
            let configDir = URL(fileURLWithPath: configPath).deletingLastPathComponent()
            try FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
            try configContent.write(toFile: configPath, atomically: true, encoding: .utf8)
            
            logManager.log("✅ rclone config written successfully", level: .debug)
            return true
        } catch {
            logManager.log("❌ Failed to write rclone config: \(error)", level: .error)
            return false
        }
    }
    
    private func testRcloneConnection(settings: BackupSettings, logManager: LogManager) async -> Bool {
        logManager.log("🚀 Testing rclone connection", level: .debug)
        
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/local/bin/rclone")
            task.arguments = ["lsd", "\(settings.remoteName):", "--timeout", "30s", "-v"]
            
            var environment = ProcessInfo.processInfo.environment
            environment["RCLONE_CONFIG"] = settings.rcloneConfigPath
            task.environment = environment
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                let success = task.terminationStatus == 0
                let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                
                if success {
                    logManager.log("✅ rclone connection successful", level: .debug)
                    logManager.log("rclone output: \(output)", level: .debug)
                } else {
                    logManager.log("❌ rclone connection failed: \(output)", level: .error)
                }
                
                continuation.resume(returning: success)
            } catch {
                logManager.log("❌ rclone execution error: \(error)", level: .error)
                continuation.resume(returning: false)
            }
        }
    }
}
