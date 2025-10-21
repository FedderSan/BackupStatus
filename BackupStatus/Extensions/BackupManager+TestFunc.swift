//
//  BackupManager+TestFunc.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 21/10/2025.
//

import Foundation

extension BackupManager {
    func testLocalConnection(_ settings: BackupSettings) async -> Bool {
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
    
    
    
    func testConnection(_ settings: BackupSettings) async -> Bool {
        // Test 1: Basic network connectivity
        guard await testNetworkReachability(settings.serverHost) else {
            logManager.log("Network unreachable", level: .error)
            return false
        }
        
        // Test 2: WebDAV connection
        guard await testWebDAVConnection(settings) else {
            logManager.log("WebDAV connection failed", level: .error)
            return false
        }
        
        logManager.log("Connection test successful", level: .info)
        return true
    }
    
    func testNetworkReachability(_ host: String) async -> Bool {
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/sbin/ping")
            task.arguments = ["-c", "1", "-W", "5000", host]
            
            do {
                try task.run()
                task.waitUntilExit()
                continuation.resume(returning: task.terminationStatus == 0)
            } catch {
                logManager.log("Ping failed: \(error)", level: .error)
                continuation.resume(returning: false)
            }
        }
    }
    
    func testWebDAVConnection(_ settings: BackupSettings) async -> Bool {
        guard let plainPassword = await settings.getPlainPassword() else {
            logManager.log("Failed to get password for WebDAV test", level: .error)
            return false
        }
        
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            
            var arguments = [
                "-s", "-f", "-X", "PROPFIND",
                "--user", "\(settings.webdavUsername):\(plainPassword)",
                "-H", "Content-Type: text/xml",
                "-H", "Depth: 0",
                "--max-time", "10"
            ]
            
            if !settings.webdavVerifySSL {
                arguments.append("-k")
            }
            
            arguments.append(settings.fullWebDAVURL)
            task.arguments = arguments
            
            let pipe = Pipe()
            task.standardError = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                if task.terminationStatus != 0 {
                    let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    logManager.log("WebDAV test failed: \(errorOutput)", level: .error)
                }
                
                continuation.resume(returning: task.terminationStatus == 0)
            } catch {
                logManager.log("WebDAV test error: \(error)", level: .error)
                continuation.resume(returning: false)
            }
        }
    }
}
