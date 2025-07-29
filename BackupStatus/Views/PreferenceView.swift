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
            
            Section("Preview") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Full WebDAV URL:")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(constructFullURL())
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .padding(8)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(4)
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
    
    private func constructFullURL() -> String {
        let scheme = webdavUseHTTPS ? "https" : "http"
        let port = Int(serverPort) != (webdavUseHTTPS ? 443 : 80) ? ":\(serverPort)" : ""
        return "\(scheme)://\(serverHost)\(port)\(webdavURL)"
    }
    
    private func generateRcloneConfigPreview() -> String {
        return """
        [\(remoteName)]
        type = webdav
        url = \(constructFullURL())
        vendor = nextcloud
        user = \(webdavUsername)
        pass = \(webdavPassword.isEmpty ? "<password>" : "***")
        \(webdavVerifySSL && webdavUseHTTPS ? "" : "insecure_skip_verify = true")
        """
    }
    
    private func testWebDAVConnection() {
        connectionTestResult = "Testing connection..."
        
        Task {
            guard let settings = settings else {
                connectionTestResult = "❌ No settings available"
                return
            }
            
            // Test WebDAV connection using curl
            let success = await testWebDAVWithCurl(settings: settings)
            
            DispatchQueue.main.async {
                if success {
                    self.connectionTestResult = "✅ WebDAV connection successful"
                } else {
                    self.connectionTestResult = "❌ WebDAV connection failed"
                }
            }
        }
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
            webdavPassword = existingSettings.webdavPassword
            webdavPath = existingSettings.webdavPath
            webdavUseHTTPS = existingSettings.webdavUseHTTPS
            webdavVerifySSL = existingSettings.webdavVerifySSL
            remoteName = existingSettings.remoteName
            remoteType = existingSettings.remoteType
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
        webdavPassword = settings.webdavPassword
        webdavPath = settings.webdavPath
        webdavUseHTTPS = settings.webdavUseHTTPS
        webdavVerifySSL = settings.webdavVerifySSL
        remoteName = settings.remoteName
        remoteType = settings.remoteType
    }
    
    private func saveSettings() {
        guard let settings = settings else { return }
        
        // Save basic settings
        settings.serverHost = serverHost
        settings.serverPort = Int(serverPort) ?? 8081
        settings.backupIntervalHours = backupInterval
        
        // Save WebDAV settings
        settings.webdavEnabled = webdavEnabled
        settings.webdavURL = webdavURL
        settings.webdavUsername = webdavUsername
        settings.webdavPassword = webdavPassword
        settings.webdavPath = webdavPath
        settings.webdavUseHTTPS = webdavUseHTTPS
        settings.webdavVerifySSL = webdavVerifySSL
        settings.remoteName = remoteName
        settings.remoteType = remoteType
        
        do {
            try modelContext.save()
            connectionTestResult = "✅ Settings saved successfully"
            
            // Optionally update rclone config file
            updateRcloneConfig()
            
        } catch {
            connectionTestResult = "❌ Failed to save settings: \(error.localizedDescription)"
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
}
