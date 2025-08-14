import SwiftUI
import SwiftData

@MainActor
struct PreferencesView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var settings: BackupSettings?
    
    // Form fields
    @State private var remoteType: RemoteType = .local
    @State private var backupInterval = 1
    
    // Source fields (NEW)
    @State private var sourcePath = ""
    @State private var excludePatterns = ""
    
    // WebDAV fields
    @State private var serverHost = ""
    @State private var serverPort = ""
    @State private var webdavURL = ""
    @State private var webdavUsername = ""
    @State private var webdavPassword = ""
    @State private var webdavPath = ""
    @State private var webdavUseHTTPS = false
    @State private var webdavVerifySSL = true
    @State private var remoteName = ""
    
    // Local fields
    @State private var localDestinationPath = ""
    @State private var localCreateDatedFolders = true
    
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
                    
                    // Source Configuration (NEW - placed first)
                    GroupBox("Source Configuration") {
                        VStack(spacing: 12) {
                            HStack {
                                Text("Source Path:")
                                    .frame(width: 120, alignment: .trailing)
                                TextField("/path/to/source", text: $sourcePath)
                                Button("Choose...") {
                                    chooseSourcePath()
                                }
                            }
                            
                            HStack(alignment: .top) {
                                Text("Exclude Patterns:")
                                    .frame(width: 120, alignment: .trailing)
                                VStack(alignment: .leading) {
                                    TextField("e.g., .DS_Store, *.tmp, *.cache", text: $excludePatterns)
                                        .help("Comma-separated patterns to exclude from backup")
                                    Text("Common patterns: .DS_Store, *.tmp, *.cache, node_modules, .git")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                            
                            if !sourcePath.isEmpty {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        Image(systemName: sourcePathExists ? "checkmark.circle.fill" : "xmark.circle.fill")
                                            .foregroundColor(sourcePathExists ? .green : .red)
                                        Text(sourcePathExists ? "Source path exists" : "Source path does not exist")
                                            .font(.caption)
                                    }
                                    
                                    if let sourceInfo = getSourceInfo() {
                                        Text("Contains: \(sourceInfo.fileCount) files, \(ByteCountFormatter.string(fromByteCount: sourceInfo.totalSize, countStyle: .file))")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(8)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(4)
                            }
                        }
                        .padding()
                    }
                    
                    // Remote Type Selection
                    GroupBox("Backup Method") {
                        VStack(spacing: 12) {
                            // Use a more explicit picker style
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Select backup destination:")
                                    .font(.headline)
                                
                                ForEach(RemoteType.allCases, id: \.self) { type in
                                    Button(action: {
                                        remoteType = type
                                        testResult = "" // Clear test results when changing type
                                    }) {
                                        HStack {
                                            Image(systemName: type.icon)
                                                .frame(width: 20)
                                            Text(type.displayName)
                                            Spacer()
                                            if remoteType == type {
                                                Image(systemName: "checkmark.circle.fill")
                                                    .foregroundColor(.blue)
                                            }
                                        }
                                        .padding(.vertical, 8)
                                        .padding(.horizontal, 12)
                                        .background(remoteType == type ? Color.blue.opacity(0.1) : Color.clear)
                                        .cornerRadius(8)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                            
                            Divider()
                            
                            HStack {
                                Text("Remote Name:")
                                    .frame(width: 100, alignment: .trailing)
                                TextField("Remote identifier", text: $remoteName)
                                    .help("Unique name for this backup configuration")
                            }
                            
                            HStack {
                                Text("Backup every:")
                                    .frame(width: 100, alignment: .trailing)
                                TextField("Hours", value: $backupInterval, format: .number)
                                    .frame(width: 60)
                                Text("hours")
                                Spacer()
                            }
                        }
                        .padding()
                    }
                    
                    // Local Configuration
                    if remoteType == .local {
                        GroupBox("Local/Network Drive Configuration") {
                            VStack(spacing: 12) {
                                HStack {
                                    Text("Destination Path:")
                                        .frame(width: 120, alignment: .trailing)
                                    TextField("/path/to/destination", text: $localDestinationPath)
                                    Button("Choose...") {
                                        chooseLocalPath()
                                    }
                                }
                                
                                HStack {
                                    Toggle("Create dated folders", isOn: $localCreateDatedFolders)
                                        .help("Creates daily and version subdirectories with timestamps")
                                    Spacer()
                                }
                                
                                if !localDestinationPath.isEmpty {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Backup structure:")
                                            .font(.caption)
                                            .foregroundColor(.secondary)
                                        Text("Daily: \(localDestinationPath)/daily/\(DateFormatter.dailyFormat.string(from: Date()))")
                                            .font(.system(.caption, design: .monospaced))
                                        Text("Versions: \(localDestinationPath)/versions/\(DateFormatter.versionFormat.string(from: Date()))")
                                            .font(.system(.caption, design: .monospaced))
                                    }
                                    .padding(8)
                                    .background(Color.blue.opacity(0.1))
                                    .cornerRadius(4)
                                }
                                
                                // Warning if source and destination are the same
                                if !sourcePath.isEmpty && !localDestinationPath.isEmpty && sourcePath == localDestinationPath {
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle.fill")
                                            .foregroundColor(.orange)
                                        Text("Source and destination cannot be the same path")
                                            .foregroundColor(.orange)
                                    }
                                    .padding(8)
                                    .background(Color.orange.opacity(0.1))
                                    .cornerRadius(4)
                                }
                            }
                            .padding()
                        }
                    }
                    
                    // WebDAV Configuration
                    if remoteType == .webdav {
                        GroupBox("Server Configuration") {
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
                            }
                            .padding()
                        }
                        
                        GroupBox("WebDAV Configuration") {
                            VStack(spacing: 12) {
                                HStack {
                                    Text("WebDAV Path:")
                                        .frame(width: 100, alignment: .trailing)
                                    TextField("Server path", text: $webdavURL)
                                        .help("e.g., /remote.php/dav/files/username")
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
                                        .help("Remote folder for backups, e.g., /BackupFolderLaptop")
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
                    }
                    
                    // Not Implemented Configuration
                    if remoteType != .local && remoteType != .webdav {
                        GroupBox("\(remoteType.displayName) Configuration") {
                            VStack {
                                Image(systemName: "wrench.and.screwdriver")
                                    .font(.largeTitle)
                                    .foregroundColor(.secondary)
                                Text("Configuration for \(remoteType.displayName) is not yet implemented")
                                    .foregroundColor(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding()
                        }
                    }
                    
                    // Preview Section
                    GroupBox("Preview") {
                        VStack(alignment: .leading, spacing: 8) {
                            // Always show source
                            if !sourcePath.isEmpty {
                                Text("Source: \(sourcePath)")
                                    .font(.system(.caption, design: .monospaced))
                                    .textSelection(.enabled)
                                    .padding(8)
                                    .background(Color.green.opacity(0.1))
                                    .cornerRadius(4)
                            }
                            
                            switch remoteType {
                            case .local:
                                if !localDestinationPath.isEmpty {
                                    Text("Destination: \(localDestinationPath)")
                                        .font(.system(.caption, design: .monospaced))
                                        .textSelection(.enabled)
                                        .padding(8)
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(4)
                                } else {
                                    Text("Please select a destination path")
                                        .foregroundColor(.secondary)
                                        .padding()
                                }
                            case .webdav:
                                if !serverHost.isEmpty && !webdavURL.isEmpty {
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
                                        .background(Color.blue.opacity(0.1))
                                        .cornerRadius(4)
                                } else {
                                    Text("Please configure server settings")
                                        .foregroundColor(.secondary)
                                        .padding()
                                }
                            default:
                                Text("Preview not available")
                                    .foregroundColor(.secondary)
                                    .padding()
                            }
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
                    
                    // Validation errors
                    let validation = validateCurrentSettings()
                    if !validation.isValid {
                        GroupBox("Configuration Issues") {
                            VStack(alignment: .leading, spacing: 4) {
                                ForEach(validation.errors, id: \.self) { error in
                                    HStack {
                                        Image(systemName: "exclamationmark.triangle")
                                            .foregroundColor(.orange)
                                        Text(error)
                                            .foregroundColor(.orange)
                                    }
                                }
                            }
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
        .frame(minWidth: 700, idealWidth: 800, maxWidth: 1200, minHeight: 600, idealHeight: 700, maxHeight: 1000)
        .onAppear {
            loadSettings()
        }
    }
    
    // MARK: - Helper Methods
    
    private var sourcePathExists: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: sourcePath, isDirectory: &isDirectory) && isDirectory.boolValue
    }
    
    private func getSourceInfo() -> (fileCount: Int, totalSize: Int64)? {
        guard sourcePathExists else { return nil }
        
        let fileManager = FileManager.default
        var fileCount = 0
        var totalSize: Int64 = 0
        
        guard let enumerator = fileManager.enumerator(atPath: sourcePath) else {
            return nil
        }
        
        while let file = enumerator.nextObject() as? String {
            let fullPath = "\(sourcePath)/\(file)"
            if let attributes = try? fileManager.attributesOfItem(atPath: fullPath),
               let fileType = attributes[.type] as? FileAttributeType,
               fileType == .typeRegular {
                fileCount += 1
                if let size = attributes[.size] as? Int64 {
                    totalSize += size
                }
            }
        }
        
        return (fileCount, totalSize)
    }
    
    private func chooseSourcePath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose source folder to backup"
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                sourcePath = url.path
            }
        }
    }
    
    private func chooseLocalPath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.message = "Choose backup destination folder"
        
        if panel.runModal() == .OK {
            if let url = panel.url {
                localDestinationPath = url.path
            }
        }
    }
    
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
    
    private func validateCurrentSettings() -> (isValid: Bool, errors: [String]) {
        var errors: [String] = []
        
        // Source validation
        if sourcePath.isEmpty {
            errors.append("Source path is required")
        } else if !sourcePathExists {
            errors.append("Source path does not exist")
        }
        
        if remoteName.isEmpty {
            errors.append("Remote name is required")
        }
        
        switch remoteType {
        case .local:
            if localDestinationPath.isEmpty {
                errors.append("Local destination path is required")
            }
            if !sourcePath.isEmpty && !localDestinationPath.isEmpty && sourcePath == localDestinationPath {
                errors.append("Source and destination paths cannot be the same")
            }
        case .webdav:
            if serverHost.isEmpty {
                errors.append("Server host is required")
            }
            if webdavUsername.isEmpty {
                errors.append("WebDAV username is required")
            }
            if webdavPassword.isEmpty {
                errors.append("WebDAV password is required")
            }
        default:
            errors.append("\(remoteType.displayName) is not yet implemented")
        }
        
        return (errors.isEmpty, errors)
    }
    
    private func loadSettings() {
        let descriptor = FetchDescriptor<BackupSettings>()
        if let existingSettings = try? modelContext.fetch(descriptor).first {
            settings = existingSettings
            populateFields(from: existingSettings)
            
            // Load password asynchronously for WebDAV
            if existingSettings.remoteType == .webdav {
                Task {
                    if let plainPassword = await existingSettings.getPlainPassword() {
                        await MainActor.run {
                            webdavPassword = plainPassword
                        }
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
        // Source fields
        sourcePath = settings.sourcePath
        excludePatterns = settings.excludePatterns
        
        // General fields
        remoteType = settings.remoteType
        backupInterval = settings.backupIntervalHours
        remoteName = settings.remoteName
        
        // WebDAV fields
        serverHost = settings.serverHost
        serverPort = String(settings.serverPort)
        webdavURL = settings.webdavURL
        webdavUsername = settings.webdavUsername
        webdavPath = settings.webdavPath
        webdavUseHTTPS = settings.webdavUseHTTPS
        webdavVerifySSL = settings.webdavVerifySSL
        
        // Local fields
        localDestinationPath = settings.localDestinationPath
        localCreateDatedFolders = settings.localCreateDatedFolders
    }
    
    private func resetToDefaults() {
        let defaults = BackupSettings()
        populateFields(from: defaults)
        webdavPassword = ""
        testResult = ""
    }
    
    private func saveSettings() {
        guard let settings = settings else { return }
        
        let validation = validateCurrentSettings()
        guard validation.isValid else {
            testResult = "❌ Please fix configuration issues before saving"
            return
        }
        
        testResult = "Saving..."
        
        Task {
            // Update source settings
            settings.sourcePath = sourcePath
            settings.excludePatterns = excludePatterns
            
            // Update basic settings
            settings.remoteType = remoteType
            settings.backupIntervalHours = backupInterval
            settings.remoteName = remoteName
            
            // Update WebDAV settings
            settings.serverHost = serverHost
            settings.serverPort = Int(serverPort) ?? 8081
            settings.webdavURL = webdavURL
            settings.webdavUsername = webdavUsername
            settings.webdavPath = webdavPath
            settings.webdavUseHTTPS = webdavUseHTTPS
            settings.webdavVerifySSL = webdavVerifySSL
            
            // Update local settings
            settings.localDestinationPath = localDestinationPath
            settings.localCreateDatedFolders = localCreateDatedFolders
            
            // Save password for WebDAV
            if remoteType == .webdav && !webdavPassword.isEmpty {
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
        let validation = validateCurrentSettings()
        guard validation.isValid else {
            testResult = "❌ Please fix configuration issues before testing"
            return
        }
        
        isTestingConnection = true
        testResult = "Testing connection..."
        
        Task {
            let success: Bool
            
            switch remoteType {
            case .local:
                success = await testLocalConnection()
            case .webdav:
                success = await testWebDAVConnection()
            default:
                success = false
                await MainActor.run {
                    testResult = "❌ Connection test not implemented for \(remoteType.displayName)"
                }
                isTestingConnection = false
                return
            }
            
            await MainActor.run {
                testResult = success ? "✅ Connection successful" : "❌ Connection failed"
                isTestingConnection = false
            }
        }
    }
    
    private func testLocalConnection() async -> Bool {
        let fileManager = FileManager.default
        
        // Test source path
        guard sourcePathExists else {
            await MainActor.run {
                testResult = "❌ Source path does not exist: \(sourcePath)"
            }
            return false
        }
        
        guard fileManager.isReadableFile(atPath: sourcePath) else {
            await MainActor.run {
                testResult = "❌ Source path is not readable"
            }
            return false
        }
        
        // Test destination path
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: localDestinationPath, isDirectory: &isDirectory) else {
            await MainActor.run {
                testResult = "❌ Destination path does not exist: \(localDestinationPath)"
            }
            return false
        }
        
        guard isDirectory.boolValue else {
            await MainActor.run {
                testResult = "❌ Destination path is not a directory"
            }
            return false
        }
        
        guard fileManager.isWritableFile(atPath: localDestinationPath) else {
            await MainActor.run {
                testResult = "❌ Destination path is not writable"
            }
            return false
        }
        
        // Test creating a temporary file
        let testFileName = UUID().uuidString
        let testFilePath = "\(localDestinationPath)/.\(testFileName).test"
        
        do {
            try "test".write(toFile: testFilePath, atomically: true, encoding: .utf8)
            try fileManager.removeItem(atPath: testFilePath)
            return true
        } catch {
            await MainActor.run {
                testResult = "❌ Cannot write to destination: \(error.localizedDescription)"
            }
            return false
        }
    }
    
    private func testWebDAVConnection() async -> Bool {
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
            
            let errorPipe = Pipe()
            task.standardError = errorPipe
            
            do {
                try task.run()
                task.waitUntilExit()
                
                if task.terminationStatus != 0 {
                    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                    Task { @MainActor in
                        testResult = "❌ WebDAV test failed: \(errorOutput)"
                    }
                }
                
                continuation.resume(returning: task.terminationStatus == 0)
            } catch {
                Task { @MainActor in
                    testResult = "❌ Connection test error: \(error.localizedDescription)"
                }
                continuation.resume(returning: false)
            }
        }
    }
}
