import SwiftUI
import SwiftData

@MainActor
struct PreferencesView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var settings: BackupSettings?
    
    // Form fields
    @State private var serverHost = ""
    @State private var serverPort = ""
    @State private var backupInterval = 1
    @State private var webdavURL = ""
    @State private var webdavUsername = ""
    @State private var webdavPassword = ""
    @State private var webdavPath = ""
    @State private var webdavUseHTTPS = false
    @State private var webdavVerifySSL = true
    @State private var remoteName = ""
    
    @State private var showingPassword = false
    @State private var testResult = ""
    @State private var isTestingConnection = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Backup Settings")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                
                Button("Test Connection") {
                    testConnection()
                }
                .disabled(isTestingConnection)
            }
            .padding()
            
            // Main form
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // Server Settings
                    GroupBox("Server") {
                        VStack(spacing: 12) {
                            HStack {
                                Text("Host:")
                                    .frame(width: 80, alignment: .trailing)
                                TextField("Server host", text: $serverHost)
                            }
                            
                            HStack {
                                Text("Port:")
                                    .frame(width: 80, alignment: .trailing)
                                TextField("Port", text: $serverPort)
                                    .frame(width: 80)
                                Spacer()
                            }
                            
                            HStack {
                                Text("Backup every:")
                                    .frame(width: 80, alignment: .trailing)
                                TextField("Hours", value: $backupInterval, format: .number)
                                    .frame(width: 60)
                                Text("hours")
                                Spacer()
                            }
                        }
                        .padding()
                    }
                    
                    // WebDAV Settings
                    GroupBox("WebDAV Configuration") {
                        VStack(spacing: 12) {
                            HStack {
                                Text("Remote Name:")
                                    .frame(width: 100, alignment: .trailing)
                                TextField("Remote name", text: $remoteName)
                            }
                            
                            HStack {
                                Text("WebDAV Path:")
                                    .frame(width: 100, alignment: .trailing)
                                TextField("Server path", text: $webdavURL)
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
                                TextField("Backup folder", text: $webdavPath)
                            }
                            
                            HStack {
                                Toggle("Use HTTPS", isOn: $webdavUseHTTPS)
                                Spacer()
                                Toggle("Verify SSL", isOn: $webdavVerifySSL)
                                    .disabled(!webdavUseHTTPS)
                            }
                        }
                        .padding()
                    }
                    
                    // URL Preview
                    GroupBox("Preview") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Base URL: \(constructBaseURL())")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(8)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                            
                            Text("Full URL: \(constructFullURL())")
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(8)
                                .background(Color.green.opacity(0.1))
                                .cornerRadius(4)
                        }
                        .padding()
                    }
                    
                    // Test Result
                    if !testResult.isEmpty {
                        GroupBox("Test Result") {
                            Text(testResult)
                                .foregroundColor(testResult.contains("✅") ? .green : .red)
                                .padding()
                        }
                    }
                }
                .padding()
            }
            
            // Bottom buttons
            HStack {
                Spacer()
                Button("Reset to Defaults") {
                    resetToDefaults()
                }
                
                Button("Save") {
                    saveSettings()
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
        .frame(width: 500, height: 600)
        .onAppear {
            loadSettings()
        }
    }
    
    // MARK: - Helper Methods
    
    private func constructBaseURL() -> String {
        let scheme = webdavUseHTTPS ? "https" : "http"
        let port = Int(serverPort) != (webdavUseHTTPS ? 443 : 80) ? ":\(serverPort)" : ""
        let cleanURL = webdavURL.hasPrefix("/") ? webdavURL : "/\(webdavURL)"
        return "\(scheme)://\(serverHost)\(port)\(cleanURL)"
    }
    
    private func constructFullURL() -> String {
        let baseURL = constructBaseURL()
        let cleanPath = webdavPath.hasPrefix("/") ? webdavPath : "/\(webdavPath)"
        return baseURL + cleanPath
    }
    
    private func loadSettings() {
        let descriptor = FetchDescriptor<BackupSettings>()
        if let existingSettings = try? modelContext.fetch(descriptor).first {
            settings = existingSettings
            populateFields(from: existingSettings)
            
            // Load password asynchronously
            Task {
                if let plainPassword = await existingSettings.getPlainPassword() {
                    await MainActor.run {
                        webdavPassword = plainPassword
                    }
                }
            }
        } else {
            // Create new settings
            let newSettings = BackupSettings()
            modelContext.insert(newSettings)
            settings = newSettings
            populateFields(from: newSettings)
        }
    }
    
    private func populateFields(from settings: BackupSettings) {
        serverHost = settings.serverHost
        serverPort = String(settings.serverPort)
        backupInterval = settings.backupIntervalHours
        webdavURL = settings.webdavURL
        webdavUsername = settings.webdavUsername
        webdavPath = settings.webdavPath
        webdavUseHTTPS = settings.webdavUseHTTPS
        webdavVerifySSL = settings.webdavVerifySSL
        remoteName = settings.remoteName
    }
    
    private func resetToDefaults() {
        let defaults = BackupSettings()
        populateFields(from: defaults)
        webdavPassword = ""
        testResult = ""
    }
    
    private func saveSettings() {
        guard let settings = settings else { return }
        
        testResult = "Saving..."
        
        Task {
            // Update settings
            settings.serverHost = serverHost
            settings.serverPort = Int(serverPort) ?? 8081
            settings.backupIntervalHours = backupInterval
            settings.webdavURL = webdavURL
            settings.webdavUsername = webdavUsername
            settings.webdavPath = webdavPath
            settings.webdavUseHTTPS = webdavUseHTTPS
            settings.webdavVerifySSL = webdavVerifySSL
            settings.remoteName = remoteName
            
            // Save password
            if !webdavPassword.isEmpty {
                await settings.setPassword(webdavPassword)
            }
            
            do {
                try modelContext.save()
                await MainActor.run {
                    testResult = "✅ Settings saved successfully"
                }
            } catch {
                await MainActor.run {
                    testResult = "❌ Failed to save: \(error.localizedDescription)"
                }
            }
        }
    }
    
    private func testConnection() {
        isTestingConnection = true
        testResult = "Testing connection..."
        
        Task {
            let success = await performConnectionTest()
            await MainActor.run {
                testResult = success ? "✅ Connection successful" : "❌ Connection failed"
                isTestingConnection = false
            }
        }
    }
    
    private func performConnectionTest() async -> Bool {
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
            
            arguments.append(constructBaseURL())
            task.arguments = arguments
            
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
