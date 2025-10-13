import SwiftUI
import SwiftData

@MainActor
struct PreferencesView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var settings: BackupSettings?
    @State private var selectedTab = 0
    
    // Form fields
    @State private var remoteType: RemoteType = .local
    @State private var backupInterval = 1
    
    // Login state items
    @State private var launchAtLogin = false
    @State private var autoStartError = ""
    
    // Source fields
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
    
    // Retention settings
    @State private var logRetentionPeriod: LogRetentionPeriod = .days30
    @State private var backupVersionRetention: BackupVersionRetention = .versions14
    
    @State private var showingPassword = false
    @State private var testResult = ""
    @State private var isTestingConnection = false
    @State private var isSaving = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            headerView
            
            Divider()
            
            // Tab View
            TabView(selection: $selectedTab) {
                generalTab
                    .tabItem {
                        Label("General", systemImage: "gear")
                    }
                    .tag(0)
                
                sourceTab
                    .tabItem {
                        Label("Source", systemImage: "folder")
                    }
                    .tag(1)
                
                destinationTab
                    .tabItem {
                        Label("Destination", systemImage: "externaldrive")
                    }
                    .tag(2)
                
                dataManagementTab
                    .tabItem {
                        Label("Data", systemImage: "archivebox")
                    }
                    .tag(3)
            }
            .padding()
            
            Divider()
            
            // Footer with actions
            footerView
        }
        .frame(minWidth: 700, idealWidth: 800, maxWidth: 1200,
               minHeight: 600, idealHeight: 700, maxHeight: 1000)
        .onAppear {
            loadSettings()
            loadAutoStartSettings()
        }
    }
    
    // MARK: - Header
    
    private var headerView: some View {
        HStack {
            Image(systemName: "gearshape.2.fill")
                .font(.title)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                Text("Backup Settings")
                    .font(.title2)
                    .fontWeight(.bold)
                
                if let validation = validateCurrentSettings(), !validation.isValid {
                    Text("\(validation.errors.count) issue\(validation.errors.count == 1 ? "" : "s") need attention")
                        .font(.caption)
                        .foregroundColor(.orange)
                }
            }
            
            Spacer()
            
            // Status indicator
            if let validation = validateCurrentSettings() {
                if validation.isValid {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .foregroundColor(.green)
                } else {
                    Label("Incomplete", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                }
            }
        }
        .padding()
    }
    
    // MARK: - General Tab
    
    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Backup Configuration
                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader("Backup Configuration", icon: "clock.arrow.circlepath")
                    
                    VStack(alignment: .leading, spacing: 16) {
                        // Remote Name
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Remote Name")
                                    .frame(width: 140, alignment: .leading)
                                    .foregroundColor(.secondary)
                                
                                TextField("backup-remote", text: $remoteName)
                                    .textFieldStyle(.roundedBorder)
                            }
                            
                            Text("A unique identifier for this backup configuration. Used internally by the backup system to track your settings.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 140)
                        }
                        
                        // Backup Interval
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Backup Interval")
                                    .frame(width: 140, alignment: .leading)
                                    .foregroundColor(.secondary)
                                
                                TextField("Hours", value: $backupInterval, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                
                                Text("hours")
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                            }
                            
                            Text("How often automatic backups should run. Set to 24 for daily backups, 12 for twice daily, etc.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 140)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                // Startup Options
                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader("Startup Options", icon: "power")
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $launchAtLogin) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Launch at Login")
                                    .fontWeight(.medium)
                                Text("Start BackupStatus automatically when you log in")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .onChange(of: launchAtLogin) { newValue in
                            setLaunchAtLogin(newValue)
                        }
                        
                        if !autoStartError.isEmpty {
                            HStack {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundColor(.orange)
                                Text(autoStartError)
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            }
                            .padding(8)
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(6)
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                Spacer()
            }
            .padding()
        }
    }
    
    // MARK: - Source Tab
    
    private var sourceTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                sectionHeader("Source Configuration", icon: "folder.fill")
                
                VStack(alignment: .leading, spacing: 16) {
                    // Source Path
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Source Folder")
                            .fontWeight(.semibold)
                        
                        HStack {
                            TextField("Choose folder to backup", text: $sourcePath)
                                .textFieldStyle(.roundedBorder)
                            
                            Button(action: chooseSourcePath) {
                                Label("Browse", systemImage: "folder")
                            }
                        }
                        
                        if !sourcePath.isEmpty {
                            if sourcePathExists {
                                statusCard(
                                    icon: "checkmark.circle.fill",
                                    color: .green,
                                    title: "Source folder exists",
                                    subtitle: sourceInfoText()
                                )
                            } else {
                                statusCard(
                                    icon: "xmark.circle.fill",
                                    color: .red,
                                    title: "Source folder not found",
                                    subtitle: "Please choose a valid folder"
                                )
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                    
                    // Exclude Patterns
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Exclude Patterns")
                            .fontWeight(.semibold)
                        
                        TextField("e.g., .DS_Store, *.tmp, *.cache", text: $excludePatterns)
                            .textFieldStyle(.roundedBorder)
                        
                        Text("Common patterns: .DS_Store, *.tmp, *.cache, node_modules, .git")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if !excludePatterns.isEmpty {
                            let patterns = excludePatterns.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
                            FlowLayout(spacing: 6) {
                                ForEach(patterns, id: \.self) { pattern in
                                    HStack(spacing: 4) {
                                        Image(systemName: "minus.circle.fill")
                                            .font(.caption2)
                                        Text(pattern)
                                            .font(.caption)
                                    }
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.orange.opacity(0.2))
                                    .cornerRadius(12)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                Spacer()
            }
            .padding()
        }
    }
    
    // MARK: - Destination Tab
    
    private var destinationTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                sectionHeader("Destination Configuration", icon: "externaldrive.fill")
                
                // Remote Type Selection
                VStack(alignment: .leading, spacing: 12) {
                    Text("Backup Method")
                        .fontWeight(.semibold)
                    
                    HStack(spacing: 12) {
                        ForEach([RemoteType.local, RemoteType.webdav], id: \.self) { type in
                            remoteTypeCard(type)
                        }
                    }
                }
                .padding()
                .background(Color(NSColor.controlBackgroundColor))
                .cornerRadius(8)
                
                // Configuration based on type
                if remoteType == .local {
                    localConfigView
                } else if remoteType == .webdav {
                    webdavConfigView
                } else {
                    notImplementedView
                }
                
                // Preview Section
                previewSection
                
                Spacer()
            }
            .padding()
        }
    }
    
    private func remoteTypeCard(_ type: RemoteType) -> some View {
        Button(action: {
            remoteType = type
            testResult = ""
        }) {
            VStack(spacing: 12) {
                Image(systemName: type.icon)
                    .font(.system(size: 32))
                    .foregroundColor(remoteType == type ? .blue : .secondary)
                
                Text(type == .local ? "Local/Network" : "Cloud (WebDAV)")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .multilineTextAlignment(.center)
                
                if remoteType == type {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(remoteType == type ? Color.blue.opacity(0.1) : Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(remoteType == type ? Color.blue : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
    
    private var localConfigView: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Local/Network Drive", icon: "externaldrive")
            
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Destination Folder")
                        .fontWeight(.semibold)
                    
                    HStack {
                        TextField("Choose backup destination", text: $localDestinationPath)
                            .textFieldStyle(.roundedBorder)
                        
                        Button(action: chooseLocalPath) {
                            Label("Browse", systemImage: "folder")
                        }
                    }
                }
                
                Toggle(isOn: $localCreateDatedFolders) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Create Version Snapshots")
                            .fontWeight(.medium)
                        Text("Creates timestamped folders for each backup")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if !localDestinationPath.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Backup Structure")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.secondary)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            structureItem("latest/", "Current backup")
                            if localCreateDatedFolders {
                                structureItem("versions/\(DateFormatter.versionFormat.string(from: Date()))/", "Dated snapshot")
                            }
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.05))
                    .cornerRadius(6)
                }
                
                if !sourcePath.isEmpty && !localDestinationPath.isEmpty && sourcePath == localDestinationPath {
                    statusCard(
                        icon: "exclamationmark.triangle.fill",
                        color: .orange,
                        title: "Invalid Configuration",
                        subtitle: "Source and destination cannot be the same"
                    )
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
    
    private var webdavConfigView: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("WebDAV Configuration", icon: "icloud")
            
            VStack(alignment: .leading, spacing: 16) {
                // Server Settings
                VStack(alignment: .leading, spacing: 12) {
                    Text("Server Settings")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Host")
                                .frame(width: 100, alignment: .leading)
                                .foregroundColor(.secondary)
                            TextField("server.example.com", text: $serverHost)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        Text("The domain name or IP address of your WebDAV server (e.g., cloud.example.com)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 100)
                    }
                    
                    HStack {
                        Text("Port")
                            .frame(width: 100, alignment: .leading)
                            .foregroundColor(.secondary)
                        TextField("8081", text: $serverPort)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        
                        Spacer()
                        
                        Toggle("HTTPS", isOn: $webdavUseHTTPS)
                        Toggle("Verify SSL", isOn: $webdavVerifySSL)
                            .disabled(!webdavUseHTTPS)
                    }
                }
                
                Divider()
                
                // Authentication
                VStack(alignment: .leading, spacing: 12) {
                    Text("Authentication")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    HStack {
                        Text("Username")
                            .frame(width: 100, alignment: .leading)
                            .foregroundColor(.secondary)
                        TextField("username", text: $webdavUsername)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    HStack {
                        Text("Password")
                            .frame(width: 100, alignment: .leading)
                            .foregroundColor(.secondary)
                        
                        Group {
                            if showingPassword {
                                TextField("password", text: $webdavPassword)
                            } else {
                                SecureField("password", text: $webdavPassword)
                            }
                        }
                        .textFieldStyle(.roundedBorder)
                        
                        Button(action: { showingPassword.toggle() }) {
                            Image(systemName: showingPassword ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                    }
                }
                
                Divider()
                
                // Paths
                VStack(alignment: .leading, spacing: 12) {
                    Text("Paths")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("WebDAV Path")
                                .frame(width: 100, alignment: .leading)
                                .foregroundColor(.secondary)
                            TextField("/remote.php/dav/files/username", text: $webdavURL)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        Text("Path to your WebDAV endpoint (e.g., /remote.php/dav/files/username for Nextcloud)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 100)
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Backup Folder")
                                .frame(width: 100, alignment: .leading)
                                .foregroundColor(.secondary)
                            TextField("/BackupFolder", text: $webdavPath)
                                .textFieldStyle(.roundedBorder)
                        }
                        
                        Text("The remote folder where your backups will be stored (e.g., /BackupFolderLaptop)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.leading, 100)
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
    
    private var notImplementedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "wrench.and.screwdriver")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            
            Text("Coming Soon")
                .font(.title3)
                .fontWeight(.semibold)
            
            Text("Configuration for \(remoteType.displayName) will be available in a future update")
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(8)
    }
    
    private var previewSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionHeader("Preview", icon: "eye")
            
            VStack(alignment: .leading, spacing: 12) {
                if !sourcePath.isEmpty {
                    previewItem(label: "Source", value: sourcePath, color: .green)
                }
                
                switch remoteType {
                case .local:
                    if !localDestinationPath.isEmpty {
                        previewItem(label: "Destination", value: localDestinationPath, color: .blue)
                    }
                case .webdav:
                    if !serverHost.isEmpty {
                        previewItem(label: "Base URL", value: constructBaseURL(), color: .blue)
                        if !webdavPath.isEmpty {
                            previewItem(label: "Full Path", value: constructFullURL(), color: .purple)
                        }
                    }
                default:
                    EmptyView()
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
    
    // MARK: - Data Management Tab
    
    private var dataManagementTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                sectionHeader("Data Management", icon: "archivebox.fill")
                
                // Log Retention
                VStack(alignment: .leading, spacing: 16) {
                    Text("Log Retention")
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Keep logs for")
                                .foregroundColor(.secondary)
                            
                            Picker("", selection: $logRetentionPeriod) {
                                ForEach(LogRetentionPeriod.allCases, id: \.self) { period in
                                    Text(period.displayName).tag(period)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 120)
                            
                            Spacer()
                        }
                        
                        Text(logRetentionPeriod.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                // Backup Version Retention
                VStack(alignment: .leading, spacing: 16) {
                    Text("Backup Version Retention")
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Keep versions")
                                .foregroundColor(.secondary)
                            
                            Picker("", selection: $backupVersionRetention) {
                                ForEach(BackupVersionRetention.allCases, id: \.self) { retention in
                                    Text(retention.displayName).tag(retention)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 140)
                            
                            Spacer()
                        }
                        
                        Text(backupVersionRetention.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if backupVersionRetention.shouldCleanup {
                            infoBox(
                                icon: "info.circle.fill",
                                color: .blue,
                                message: "Older backup versions will be automatically deleted after each backup"
                            )
                        } else {
                            infoBox(
                                icon: "exclamationmark.triangle.fill",
                                color: .orange,
                                message: "All backup versions will be kept - monitor disk space usage carefully"
                            )
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                Spacer()
            }
            .padding()
        }
    }
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack(spacing: 12) {
            if !testResult.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: testResult.contains("✅") ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(testResult.contains("✅") ? .green : .red)
                    Text(testResult)
                        .font(.subheadline)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(testResult.contains("✅") ? Color.green.opacity(0.1) : Color.red.opacity(0.1))
                .cornerRadius(6)
            }
            
            Spacer()
            
            Button("Test Connection") {
                testConnection()
            }
            .disabled(isTestingConnection)
            
            Button("Reset to Defaults") {
                resetToDefaults()
            }
            
            Button(action: saveSettings) {
                HStack {
                    if isSaving {
                        ProgressView()
                            .scaleEffect(0.7)
                    }
                    Text("Save Settings")
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving)
        }
        .padding()
    }
    
    // MARK: - Helper Views
    
    private func sectionHeader(_ title: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.blue)
            Text(title)
                .font(.title3)
                .fontWeight(.bold)
        }
    }
    
    private func statusCard(icon: String, color: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(color)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(color.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func structureItem(_ path: String, _ description: String) -> some View {
        HStack {
            Text(path)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.blue)
            Text("→")
                .font(.caption)
                .foregroundColor(.secondary)
            Text(description)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func previewItem(label: String, value: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(color)
                .textSelection(.enabled)
        }
    }
    
    private func infoBox(icon: String, color: Color, message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(color)
            Text(message)
                .font(.caption)
                .foregroundColor(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }
    
    // MARK: - Helper Methods
    
    private var sourcePathExists: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: sourcePath, isDirectory: &isDirectory) && isDirectory.boolValue
    }
    
    private func sourceInfoText() -> String {
        if let info = getSourceInfo() {
            return "\(info.fileCount) files, \(ByteCountFormatter.string(fromByteCount: info.totalSize, countStyle: .file))"
        }
        return ""
    }
    
    private func loadAutoStartSettings() {
        launchAtLogin = LoginItemManager.shared.isEnabled
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItemManager.shared.setEnabled(enabled)
            autoStartError = ""
        } catch {
            autoStartError = "Failed to update login settings"
            launchAtLogin = LoginItemManager.shared.isEnabled
        }
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
    
    private func validateCurrentSettings() -> (isValid: Bool, errors: [String])? {
        var errors: [String] = []
        
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
                errors.append("Source and destination cannot be the same")
            }
        case .webdav:
            if serverHost.isEmpty {
                errors.append("Server host is required")
            }
            if webdavUsername.isEmpty {
                errors.append("Username is required")
            }
            if webdavPassword.isEmpty {
                errors.append("Password is required")
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
            let newSettings = BackupSettings()
            modelContext.insert(newSettings)
            settings = newSettings
            populateFields(from: newSettings)
        }
    }
    
    private func populateFields(from settings: BackupSettings) {
        sourcePath = settings.sourcePath
        excludePatterns = settings.excludePatterns
        remoteType = settings.remoteType
        backupInterval = settings.backupIntervalHours
        remoteName = settings.remoteName
        serverHost = settings.serverHost
        serverPort = String(settings.serverPort)
        webdavURL = settings.webdavURL
        webdavUsername = settings.webdavUsername
        webdavPath = settings.webdavPath
        webdavUseHTTPS = settings.webdavUseHTTPS
        webdavVerifySSL = settings.webdavVerifySSL
        localDestinationPath = settings.localDestinationPath
        localCreateDatedFolders = settings.localCreateDatedFolders
        logRetentionPeriod = settings.logRetentionPeriod
        backupVersionRetention = settings.backupVersionRetention
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
        guard validation?.isValid == true else {
            testResult = "❌ Please fix configuration issues"
            return
        }
        
        isSaving = true
        testResult = "Saving..."
        
        Task {
            settings.sourcePath = sourcePath
            settings.excludePatterns = excludePatterns
            settings.remoteType = remoteType
            settings.backupIntervalHours = backupInterval
            settings.remoteName = remoteName
            settings.serverHost = serverHost
            settings.serverPort = Int(serverPort) ?? 8081
            settings.webdavURL = webdavURL
            settings.webdavUsername = webdavUsername
            settings.webdavPath = webdavPath
            settings.webdavUseHTTPS = webdavUseHTTPS
            settings.webdavVerifySSL = webdavVerifySSL
            settings.localDestinationPath = localDestinationPath
            settings.localCreateDatedFolders = localCreateDatedFolders
            settings.logRetentionPeriod = logRetentionPeriod
            settings.backupVersionRetention = backupVersionRetention
            
            if remoteType == .webdav && !webdavPassword.isEmpty {
                await settings.setPassword(webdavPassword)
            }
            
            do {
                try modelContext.save()
                await MainActor.run {
                    testResult = "✅ Settings saved successfully"
                    isSaving = false
                }
            } catch {
                await MainActor.run {
                    testResult = "❌ Failed to save"
                    isSaving = false
                }
            }
        }
    }
    
    private func testConnection() {
        let validation = validateCurrentSettings()
        guard validation?.isValid == true else {
            testResult = "❌ Fix configuration issues first"
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
                    testResult = "❌ Not implemented for \(remoteType.displayName)"
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
        
        guard sourcePathExists else {
            await MainActor.run {
                testResult = "❌ Source path does not exist"
            }
            return false
        }
        
        guard fileManager.isReadableFile(atPath: sourcePath) else {
            await MainActor.run {
                testResult = "❌ Source path not readable"
            }
            return false
        }
        
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: localDestinationPath, isDirectory: &isDirectory) else {
            await MainActor.run {
                testResult = "❌ Destination path does not exist"
            }
            return false
        }
        
        guard isDirectory.boolValue else {
            await MainActor.run {
                testResult = "❌ Destination is not a directory"
            }
            return false
        }
        
        guard fileManager.isWritableFile(atPath: localDestinationPath) else {
            await MainActor.run {
                testResult = "❌ Destination not writable"
            }
            return false
        }
        
        let testFileName = UUID().uuidString
        let testFilePath = "\(localDestinationPath)/.\(testFileName).test"
        
        do {
            try "test".write(toFile: testFilePath, atomically: true, encoding: .utf8)
            try fileManager.removeItem(atPath: testFilePath)
            return true
        } catch {
            await MainActor.run {
                testResult = "❌ Cannot write to destination"
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
                        testResult = "❌ Connection failed: \(errorOutput)"
                    }
                }
                
                continuation.resume(returning: task.terminationStatus == 0)
            } catch {
                Task { @MainActor in
                    testResult = "❌ Test error: \(error.localizedDescription)"
                }
                continuation.resume(returning: false)
            }
        }
    }
}

// MARK: - Flow Layout for Tags
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = FlowResult(
            in: proposal.replacingUnspecifiedDimensions().width,
            subviews: subviews,
            spacing: spacing
        )
        return result.size
    }
    
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = FlowResult(
            in: bounds.width,
            subviews: subviews,
            spacing: spacing
        )
        for (index, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + result.frames[index].minX,
                                     y: bounds.minY + result.frames[index].minY),
                         proposal: .unspecified)
        }
    }
    
    struct FlowResult {
        var size: CGSize = .zero
        var frames: [CGRect] = []
        
        init(in maxWidth: CGFloat, subviews: Subviews, spacing: CGFloat) {
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0
            
            for subview in subviews {
                let size = subview.sizeThatFits(.unspecified)
                
                if x + size.width > maxWidth && x > 0 {
                    x = 0
                    y += lineHeight + spacing
                    lineHeight = 0
                }
                
                frames.append(CGRect(x: x, y: y, width: size.width, height: size.height))
                
                lineHeight = max(lineHeight, size.height)
                x += size.width + spacing
            }
            
            self.size = CGSize(width: maxWidth, height: y + lineHeight)
        }
    }
}
