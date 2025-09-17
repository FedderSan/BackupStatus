//
//  DebugView.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 17/09/2025.
//

import SwiftUI

struct DebugView: View {
    @State private var debugOutput = ""
    @State private var isRunning = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Backup Debug Tools")
                .font(.title2)
                .fontWeight(.bold)
            
            Button("Test External Tools") {
                testExternalTools()
            }
            .disabled(isRunning)
            
            Button("Test Permissions") {
                testPermissions()
            }
            .disabled(isRunning)
            
            Button("Test Paths") {
                testPaths()
            }
            .disabled(isRunning)
            
            ScrollView {
                Text(debugOutput)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(height: 400)
            .background(Color.black.opacity(0.1))
            .cornerRadius(8)
            
            Button("Clear") {
                debugOutput = ""
            }
        }
        .padding()
        .frame(width: 600, height: 500)
    }
    
    private func addOutput(_ text: String) {
        DispatchQueue.main.async {
            debugOutput += text + "\n"
        }
    }
    
    private func testExternalTools() {
        isRunning = true
        debugOutput = ""
        
        Task {
            defer { isRunning = false }
            
            await addOutput("=== Testing External Tools ===")
            
            // Test rclone
            let rclonePaths = [
                "/usr/local/bin/rclone",
                "/opt/homebrew/bin/rclone",
                "/usr/bin/rclone"
            ]
            
            var rcloneFound = false
            for path in rclonePaths {
                if FileManager.default.fileExists(atPath: path) {
                    await addOutput("✅ Found rclone at: \(path)")
                    rcloneFound = true
                    
                    // Test rclone version
                    let version = await runCommand(path, ["version"])
                    await addOutput("rclone version output: \(version)")
                    break
                }
            }
            
            if !rcloneFound {
                await addOutput("❌ rclone not found in common locations")
                
                // Try 'which' command
                let whichResult = await runCommand("/usr/bin/which", ["rclone"])
                if !whichResult.isEmpty {
                    await addOutput("💡 Found rclone via 'which': \(whichResult)")
                } else {
                    await addOutput("❌ 'which rclone' returned nothing")
                }
            }
            
            // Test rsync
            let rsyncPath = "/usr/bin/rsync"
            if FileManager.default.fileExists(atPath: rsyncPath) {
                await addOutput("✅ Found rsync at: \(rsyncPath)")
                let version = await runCommand(rsyncPath, ["--version"])
                await addOutput("rsync version: \(version.prefix(100))")
            } else {
                await addOutput("❌ rsync not found at: \(rsyncPath)")
            }
            
            // Test other tools
            let tools = [
                "/usr/bin/curl": ["--version"],
                "/sbin/ping": ["-c", "1", "8.8.8.8"],
                "/usr/bin/find": ["--version"],
                "/usr/bin/du": ["--version"]
            ]
            
            for (path, args) in tools {
                if FileManager.default.fileExists(atPath: path) {
                    await addOutput("✅ Found: \(path)")
                } else {
                    await addOutput("❌ Missing: \(path)")
                }
            }
        }
    }
    
    private func testPermissions() {
        isRunning = true
        
        Task {
            defer { isRunning = false }
            
            await addOutput("=== Testing Permissions ===")
            
            // Test home directory access
            let homeDir = FileManager.default.homeDirectoryForCurrentUser.path
            await addOutput("Home directory: \(homeDir)")
            
            if FileManager.default.isReadableFile(atPath: homeDir) {
                await addOutput("✅ Home directory is readable")
            } else {
                await addOutput("❌ Home directory is not readable")
            }
            
            // Test config directory creation
            let configPath = "\(homeDir)/.config/rclone"
            do {
                try FileManager.default.createDirectory(atPath: configPath, withIntermediateDirectories: true)
                await addOutput("✅ Can create config directory: \(configPath)")
                
                // Test writing to config file
                let testConfig = "[test]\ntype = local\n"
                let configFile = "\(configPath)/test.conf"
                try testConfig.write(toFile: configFile, atomically: true, encoding: .utf8)
                await addOutput("✅ Can write to config file")
                
                // Clean up
                try? FileManager.default.removeItem(atPath: configFile)
                
            } catch {
                await addOutput("❌ Cannot create config directory: \(error)")
            }
            
            // Test running a simple process
            let result = await runCommand("/bin/echo", ["Hello from packaged app"])
            if result.contains("Hello") {
                await addOutput("✅ Can execute external processes")
            } else {
                await addOutput("❌ Cannot execute external processes: \(result)")
            }
        }
    }
    
    private func testPaths() {
        isRunning = true
        
        Task {
            defer { isRunning = false }
            
            await addOutput("=== Testing Paths ===")
            
            // Test PATH environment
            let path = ProcessInfo.processInfo.environment["PATH"] ?? ""
            await addOutput("PATH: \(path)")
            
            // Test common directories
            let commonDirs = [
                "/usr/local/bin",
                "/opt/homebrew/bin",
                "/usr/bin",
                "/bin"
            ]
            
            for dir in commonDirs {
                if FileManager.default.fileExists(atPath: dir) {
                    await addOutput("✅ Directory exists: \(dir)")
                } else {
                    await addOutput("❌ Directory missing: \(dir)")
                }
            }
        }
    }
    
    private func runCommand(_ executable: String, _ arguments: [String]) async -> String {
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: executable)
            task.arguments = arguments
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let output = String(data: data, encoding: .utf8) ?? "No output"
                continuation.resume(returning: output.trimmingCharacters(in: .whitespacesAndNewlines))
            } catch {
                continuation.resume(returning: "Error: \(error)")
            }
        }
    }
}

// Add this to your main app to help debug:
// Window("Debug", id: "debug") {
//     DebugView()
// }
