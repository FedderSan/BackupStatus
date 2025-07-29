//
//  RClonePasswordHelper.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 29/07/2025.
//

//
//  RclonePasswordHelper.swift
//  BackupStatus
//
//  Helper for obscuring passwords for rclone configuration
//

import Foundation

class RclonePasswordHelper {
    static let shared = RclonePasswordHelper()
    private let rclonePath = "/usr/local/bin/rclone"
    
    private init() {}
    
    /// Obscures a plain text password using rclone's obscure command
    func obscurePassword(_ plainPassword: String) async -> String? {
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: rclonePath)
            task.arguments = ["obscure", plainPassword]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                if task.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: output)
                } else {
                    let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    print("Failed to obscure password: \(errorOutput)")
                    continuation.resume(returning: nil)
                }
            } catch {
                print("Error running rclone obscure: \(error)")
                continuation.resume(returning: nil)
            }
        }
    }
    
    /// Reveals an obscured password using rclone's reveal command
    func revealPassword(_ obscuredPassword: String) async -> String? {
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: rclonePath)
            task.arguments = ["reveal", obscuredPassword]
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                if task.terminationStatus == 0 {
                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
                    continuation.resume(returning: output)
                } else {
                    continuation.resume(returning: nil)
                }
            } catch {
                print("Error running rclone reveal: \(error)")
                continuation.resume(returning: nil)
            }
        }
    }
}
