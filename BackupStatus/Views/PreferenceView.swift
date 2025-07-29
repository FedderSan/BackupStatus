//
//  PreferenceView.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 27/07/2025.
//
import SwiftUI
import SwiftData

@MainActor
struct PreferencesView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    
    // Basic settings
    @State private var serverHost = "MiniServer-DF"
    @State private var serverPort = "8081"
    @State private var backupInterval = 1
    
    // WebDAV settings
    @State private var webdavEnabled = true
    @State private var webdavURL = "/remote.php/dav/files/daniel"
    @State private var webdavUsername = "daniel"
    @State private var webdavPassword = ""
    @State private var webdavPath = "/BackupFolderLaptop"
    @State private var webdavUseHTTPS = false
    @State private var webdavVerifySSL = true
    @State private var remoteName = "nextcloud-backup"
    @State private var remoteType = RemoteType.webdav
    
    @State private var settings: BackupSettings?
    @State private var selectedTab = 0
    @State private var showingTestConnection = false
    @State private var connectionTestResult: String = ""
    @State private var showingPassword = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack {
                Text("Backup Preferences")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Test Connection") {
                    testWebDAVConnection()
                }
                .disabled(!webdavEnabled)
            }
            .padding()
            
            // Tab View
            TabView(selection: $selectedTab) {
                // Basic Settings Tab
                basicSettingsView
                    .tabItem {
                        Label("General", systemImage: "gear")
                    }
                    .tag(0)
                
                // WebDAV Settings Tab
                webdavSettingsView
                    .tabItem {
                        Label("WebDAV", systemImage: "server.rack")
                    }
                    .tag(1)
                
                // Advanced Settings Tab
                advancedSettingsView
                    .tabItem {
                        Label("Advanced", systemImage: "slider.horizontal.3")
                    }
                    .tag(2)
            }
            
            // Bottom buttons
            HStack {
                if !connectionTestResult.isEmpty {
                    Text(connectionTestResult)
                        .font(.caption)
                        .foregroundColor(connectionTestResult.contains("Success") ? .green : .red)
                }
                Spacer()
                Button("Cancel") {
                    loadSettings()
                }
                Button("Save") {
                    saveSettings()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 500, height: 450)
        .onAppear {
            loadSettings()
        }
    }
    
    private var basicSettingsView: some View {
        Form {
            Section("Server Connection") {
                HStack {
                    Text("Host:")
                        .frame(width: 80, alignment: .trailing)
                    TextField("Server Host", text: $serverHost)
                }
                
                HStack {
                    Text("Port:")
                        .frame(width: 80, alignment: .trailing)
                    TextField("Port", text: $serverPort)
                        .frame(width: 80)
                    Spacer()
                }
            }
            
            Section("Backup Schedule") {
                HStack {
                    Text("Check interval:")
                        .frame(width: 80, alignment: .trailing)
                    TextField("Hours", value: $backupInterval, format: .number)
                        .frame(width: 60)
                    Text("hours")
                }
            }
        }
        .padding()
    }
    
    private var webdavSettingsView: some View {
        Form {
            Section("WebDAV Configuration") {
                Toggle("Enable WebDAV", isOn: $webdavEnabled)
                
                Group {
                    HStack {
                        Text("Remote Name:")
                            .frame(width: 100, alignment: .trailing)
                        TextField("Remote name", text: $remoteName)
                    }
                    
                    HStack {
                        Text("WebDAV URL:")
                            .frame(width: 100, alignment: .trailing)
                        TextField("Path on server", text: $webdavURL)
                    }
                    
                    HStack {
                        Text("Username:")
                            .frame(width: 100, alignment: .trailing)
                        TextField("Username", text: $webdavUsername)
                    }
                    
                    HStack {
                        Text("Password:")
                            .frame(width: 100, alignment: .trailing)
                        HStack {
                            if showingPassword {
                                TextField("Password", text: $webdavPassword)
                            } else {
                                SecureField("Password", text: $webdavPassword)
                            }
                            Button(action: { showingPassword.toggle() }) {
                                Image(systemName: showingPassword ? "eye.slash" : "eye")
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    
                    HStack {
                        Text("Backup Path:")
                            .frame(width: 100, alignment: .trailing)
                        TextField("Remote path", text: $webdavPath)
                    }
                }
                .disabled(!webdavEnabled)
            }
            
            Section("Security") {
                Toggle("Use HTTPS", isOn: $webdavUseHTTPS)
                    .disabled(!webdavEnabled)
                Toggle("Verify SSL Certificate", isOn: $webdavVerifySSL)
                    .disabled(!webdavEnabled || !webdavUseHTTPS)
            }
            
            // Update the Preview section in webdavSettingsView
            Section("Preview") {
                VStack(alignment: .leading, spacing: 8) {
                    // Base WebDAV URL (used for rclone config)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Base WebDAV URL (for rclone):")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(constructFullURL())
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .background(Color.blue.opacity(0.1))
                            .cornerRadius(4)
                    }
                    
                    // Full backup URL (what will actually be accessed)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Full backup URL (base + backup path):")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(constructFullURLWithPath())
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .padding(8)
                            .background(Color.green.opacity(0.1))
                            .cornerRadius(4)
                    }
                }
            }
        }
        .padding()
    }
    
    private var advancedSettingsView: some View {
        Form {
            Section("Remote Type") {
                Picker("Type:", selection: $remoteType) {
                    ForEach(RemoteType.allCases, id: \.self) { type in
                        Text(type.displayName).tag(type)
                    }
                }
                .pickerStyle(.segmented)
            }
            
            Section("Retry Settings") {
                HStack {
                    Text("Max Retries:")
                        .frame(width: 100, alignment: .trailing)
                    TextField("Retries", value: .constant(3), format: .number)
                        .frame(width: 60)
                }
                
                HStack {
                    Text("Retry Delay:")
                        .frame(width: 100, alignment: .trailing)
                    TextField("Seconds", value: .constant(30), format: .number)
                        .frame(width: 60)
                    Text("seconds")
                }
            }
            
            Section("rclone Configuration") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Generated rclone config:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ScrollView {
                        Text(generateRcloneConfigPreview())
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(height: 100)
                    .padding(8)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(4)
                }
            }
        }
        .padding()
    }
    
    // Replace the constructFullURL method in PreferencesView.swift
    private func constructFullURL() -> String {
        let scheme = webdavUseHTTPS ? "https" : "http"
        let port = Int(serverPort) != (webdavUseHTTPS ? 443 : 80) ? ":\(serverPort)" : ""
        
        // Ensure webdavURL starts with /
        let cleanWebdavURL = webdavURL.hasPrefix("/") ? webdavURL : "/\(webdavURL)"
        
        return "\(scheme)://\(serverHost)\(port)\(cleanWebdavURL)"
    }
    
    // Add this new method to show the full URL with backup path
    private func constructFullURLWithPath() -> String {
        let baseURL = constructFullURL()
        let cleanPath = webdavPath.hasPrefix("/") ? webdavPath : "/\(webdavPath)"
        return baseURL + cleanPath
    }
    
    // Update the generateRcloneConfigPreview method
    private func generateRcloneConfigPreview() -> String {
        let sslVerify = webdavVerifySSL && webdavUseHTTPS ? "" : "\ninsecure_skip_verify = true"
        
        return """
        [\(remoteName)]
        type = webdav
        url = \(constructFullURL())
        vendor = nextcloud
        user = \(webdavUsername)
        pass = \(webdavPassword.isEmpty ? "<password will be obscured>" : "<password obscured>")\(sslVerify)
        """
    }
    
    
    
    private func testWebDAVWithCurl(settings: BackupSettings) async -> Bool {
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            
            var arguments = [
                "-s", "-f", "-X", "PROPFIND",
                "--user", "\(webdavUsername):\(webdavPassword)",
                "-H", "Content-Type: text/xml",
                "-H", "Depth: 0",
                "--max-time", "10"
            ]
            
            if !webdavVerifySSL {
                arguments.append("-k")
            }
            
            arguments.append(constructFullURL())
            task.arguments = arguments
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                continuation.resume(returning: task.terminationStatus == 0)
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
    
    // Replace the loadSettings method in PreferencesView.swift
    private func loadSettings() {
        let descriptor = FetchDescriptor<BackupSettings>()
        if let existingSettings = try? modelContext.fetch(descriptor).first {
            settings = existingSettings
            serverHost = existingSettings.serverHost
            serverPort = String(existingSettings.serverPort)
            backupInterval = existingSettings.backupIntervalHours
            
            // Load WebDAV settings
            webdavEnabled = existingSettings.webdavEnabled
            webdavURL = existingSettings.webdavURL
            webdavUsername = existingSettings.webdavUsername
            webdavPath = existingSettings.webdavPath
            webdavUseHTTPS = existingSettings.webdavUseHTTPS
            webdavVerifySSL = existingSettings.webdavVerifySSL
            remoteName = existingSettings.remoteName
            remoteType = existingSettings.remoteType
            
            // Load the plain password asynchronously
            Task {
                if let plainPassword = await existingSettings.getPlainPassword() {
                    await MainActor.run {
                        webdavPassword = plainPassword
                    }
                }
            }
        } else {
            // Create default settings
            let newSettings = BackupSettings()
            modelContext.insert(newSettings)
            settings = newSettings
            loadDefaultValues(from: newSettings)
        }
    }
    
    private func loadDefaultValues(from settings: BackupSettings) {
        serverHost = settings.serverHost
        serverPort = String(settings.serverPort)
        backupInterval = settings.backupIntervalHours
        webdavEnabled = settings.webdavEnabled
        webdavURL = settings.webdavURL
        webdavUsername = settings.webdavUsername
        webdavPath = settings.webdavPath
        webdavUseHTTPS = settings.webdavUseHTTPS
        webdavVerifySSL = settings.webdavVerifySSL
        remoteName = settings.remoteName
        remoteType = settings.remoteType
        
        // For new settings, the password will be empty initially
        webdavPassword = ""
        
        // If there's an obscured password, try to reveal it
        Task {
            if !settings.webdavPasswordObscured.isEmpty,
               let plainPassword = await settings.getPlainPassword() {
                await MainActor.run {
                    webdavPassword = plainPassword
                }
            }
        }
    }
    
    // Replace the saveSettings method in PreferencesView.swift
    private func saveSettings() {
        guard let settings = settings else { return }
        
        connectionTestResult = "Saving settings..."
        
        Task {
            // Save basic settings
            settings.serverHost = serverHost
            settings.serverPort = Int(serverPort) ?? 8081
            settings.backupIntervalHours = backupInterval
            
            // Save WebDAV settings
            settings.webdavEnabled = webdavEnabled
            settings.webdavURL = webdavURL
            settings.webdavUsername = webdavUsername
            settings.webdavPath = webdavPath
            settings.webdavUseHTTPS = webdavUseHTTPS
            settings.webdavVerifySSL = webdavVerifySSL
            settings.remoteName = remoteName
            settings.remoteType = remoteType
            
            // Obscure and save the password
            if !webdavPassword.isEmpty {
                await settings.setPassword(webdavPassword)
            }
            
            do {
                try modelContext.save()
                
                // Update rclone config with obscured password
                try settings.updateRcloneConfig()
                
                await MainActor.run {
                    connectionTestResult = "✅ Settings saved successfully"
                }
            } catch {
                await MainActor.run {
                    connectionTestResult = "❌ Failed to save settings: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func updateRcloneConfig() {
        guard let settings = settings else { return }
        
        do {
            try RcloneConfigHelper.shared.updateConfiguration(with: settings)
            connectionTestResult = "✅ rclone configuration updated successfully"
        } catch {
            connectionTestResult = "❌ Failed to update rclone config: \(error.localizedDescription)"
        }
    }
    
    // Replace the testWebDAVConnection method in PreferencesView.swift
    private func testWebDAVConnection() {
        connectionTestResult = "Testing connection..."
        
        Task {
            // Create a temporary settings object for testing
            let tempSettings = BackupSettings()
            tempSettings.serverHost = serverHost
            tempSettings.serverPort = Int(serverPort) ?? 8081
            tempSettings.webdavEnabled = webdavEnabled
            tempSettings.webdavURL = webdavURL
            tempSettings.webdavUsername = webdavUsername
            tempSettings.webdavPath = webdavPath
            tempSettings.webdavUseHTTPS = webdavUseHTTPS
            tempSettings.webdavVerifySSL = webdavVerifySSL
            
            // Set the password for testing
            await tempSettings.setPassword(webdavPassword)
            
            // Test WebDAV connection using the plain password
            let success = await testWebDAVWithSettings(tempSettings)
            
            await MainActor.run {
                if success {
                    self.connectionTestResult = "✅ WebDAV connection successful"
                } else {
                    self.connectionTestResult = "❌ WebDAV connection failed"
                }
            }
        }
    }

    // Update the testWebDAVWithSettings method to use the correct URL
    private func testWebDAVWithSettings(_ settings: BackupSettings) async -> Bool {
        guard let plainPassword = await settings.getPlainPassword() else {
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
            
            // Use the base WebDAV URL for connection testing
            arguments.append(settings.fullWebDAVURL)
            task.arguments = arguments
            
            let pipe = Pipe()
            task.standardOutput = pipe
            task.standardError = pipe
            
            do {
                try task.run()
                task.waitUntilExit()
                continuation.resume(returning: task.terminationStatus == 0)
            } catch {
                continuation.resume(returning: false)
            }
        }
    }
}
