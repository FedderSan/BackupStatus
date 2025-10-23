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
    
    // Debug Mode
    @AppStorage("debugModeEnabled") private var debugModeEnabled = false
    
    // NEW: rsync status
    @State private var rsyncStatus: RsyncStatus = .unknown
    @State private var rsyncVersion: String?
    
    @State private var showingPassword = false
    @State private var testResult = ""
    @State private var isTestingConnection = false
    @State private var isSaving = false
    
    // FIX: Prevent multiple reloads of settings
    @State private var hasLoadedInitialSettings = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with Debug Indicator
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
                
                advancedTab
                    .tabItem {
                        Label("Advanced", systemImage: "wrench.and.screwdriver")
                    }
                    .tag(4)
            }
            .padding()
            
            Divider()
            
            // Footer with actions
            footerView
        }
        .frame(minWidth: 700, idealWidth: 800, maxWidth: 1200,
               minHeight: 600, idealHeight: 700, maxHeight: 1000)
        .onAppear {
            if !hasLoadedInitialSettings {
                loadSettings()
                loadAutoStartSettings()
                checkRsyncStatus()
                hasLoadedInitialSettings = true
            }
        }
        .onDisappear {
            hasLoadedInitialSettings = false
        }
    }
    
    // MARK: - Header with Debug Badge
    
    private var headerView: some View {
        HStack {
            Image(systemName: "gearshape.2.fill")
                .font(.title)
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 8) {
                    Text("Backup Settings")
                        .font(.title2)
                        .fontWeight(.bold)
                    
                    // Debug Mode Badge
                    #if DEBUG
                    debugBadge(text: "DEV", color: .purple)
                    #else
                    if debugModeEnabled {
                        debugBadge(text: "DEBUG", color: .orange)
                    }
                    #endif
                }
                
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
    
    // Debug Badge Helper
    private func debugBadge(text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: "ant.circle.fill")
                .font(.caption2)
            Text(text)
                .font(.caption2)
                .fontWeight(.bold)
        }
        .foregroundColor(color)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(color.opacity(0.15))
        .cornerRadius(4)
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }
    
    // MARK: - Advanced Tab with rsync Status
    
    private var advancedTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                sectionHeader("Advanced Settings", icon: "wrench.and.screwdriver")
                
                // rsync Status Section
                rsyncStatusSection
                
                // Debug Mode Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Developer Options")
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $debugModeEnabled) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Enable Debug Mode")
                                    .fontWeight(.medium)
                                Text("Show advanced debugging tools in the menu bar")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        if debugModeEnabled {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "info.circle.fill")
                                        .foregroundColor(.blue)
                                    Text("Debug tools are now available")
                                        .font(.subheadline)
                                        .foregroundColor(.blue)
                                }
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.blue.opacity(0.1))
                                .cornerRadius(8)
                                
                                Text("Available debug tools:")
                                    .font(.caption)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    debugToolItem("🔍 Debug Connection", "Test connection with detailed logging")
                                    debugToolItem("🔧 Debug rclone Config", "View current rclone configuration")
                                    debugToolItem("🔐 Debug Password", "Test password encryption/decryption")
                                    debugToolItem("📊 Run Diagnostics", "Full system diagnostics")
                                    debugToolItem("📈 Version Stats", "View backup version statistics")
                                    debugToolItem("🗑️ Clean Old Versions", "Manually trigger version cleanup")
                                    debugToolItem("🧹 Clean Old Logs", "Manually trigger log cleanup")
                                }
                                .padding()
                                .background(Color(NSColor.controlBackgroundColor))
                                .cornerRadius(8)
                            }
                        }
                    }
                    .padding()
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(8)
                }
                
                // Application Info Section
                VStack(alignment: .leading, spacing: 16) {
                    Text("Application Info")
                        .fontWeight(.semibold)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        infoRow(label: "Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown")
                        infoRow(label: "Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "Unknown")
                        infoRow(label: "Bundle ID", value: Bundle.main.bundleIdentifier ?? "Unknown")
                        
                        #if DEBUG
                        infoRow(label: "Build Type", value: "Debug", color: .purple)
                        #else
                        infoRow(label: "Build Type", value: "Release", color: .green)
                        #endif
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
    
    // MARK: - rsync Status Section
    
    private var rsyncStatusSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Required Tools")
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button(action: checkRsyncStatus) {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
                .buttonStyle(.borderless)
            }
            
            VStack(alignment: .leading, spacing: 12) {
                // rsync status card
                HStack(spacing: 12) {
                    Image(systemName: rsyncStatus.icon)
                        .font(.title2)
                        .foregroundColor(rsyncStatus.color)
                        .frame(width: 40)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("GNU rsync")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        
                        Text(rsyncStatus.message)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if let version = rsyncVersion {
                            Text(version)
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                        }
                    }
                    
                    Spacer()
                    
                    // Show install button when not installed or only openrsync
                    if rsyncStatus == .notInstalled || rsyncStatus == .openRsync {
                        Menu {
                            Button(action: openTerminal) {
                                Label("Open Terminal", systemImage: "terminal")
                            }
                            
                            Button(action: copyInstallCommand) {
                                Label("Copy Install Command", systemImage: "doc.on.doc")
                            }
                            
                            Divider()
                            
                            Button(action: openInstallInstructions) {
                                Label("View Homebrew Instructions", systemImage: "safari")
                            }
                        } label: {
                            Label("Install", systemImage: "arrow.down.circle.fill")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
                .padding()
                .background(rsyncStatus.backgroundColor)
                .cornerRadius(12)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(rsyncStatus.color.opacity(0.3), lineWidth: 2)
                )
                
                // Installation instructions (when needed)
                if rsyncStatus == .notInstalled || rsyncStatus == .openRsync {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.orange)
                            Text("Action Required")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        
                        if rsyncStatus == .openRsync {
                            Text("macOS includes openrsync, which is not fully compatible with this app. You need to install the real GNU rsync from Homebrew.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("This app requires GNU rsync for advanced backup features. Install it using Homebrew.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Installation steps:")
                                .font(.caption)
                                .fontWeight(.semibold)
                            
                            VStack(alignment: .leading, spacing: 6) {
                                installStep(number: 1, text: "Install Homebrew (if not installed): brew.sh")
                                installStep(number: 2, text: "Open Terminal app")
                                installStep(number: 3, text: "Run: brew install rsync")
                                installStep(number: 4, text: "Click 'Refresh' above to verify")
                            }
                        }
                        
                        HStack(spacing: 8) {
                            Button(action: openTerminal) {
                                Label("Open Terminal", systemImage: "terminal")
                            }
                            
                            Button(action: copyInstallCommand) {
                                Label("Copy Command", systemImage: "doc.on.doc")
                            }
                            
                            Button(action: openInstallInstructions) {
                                Label("Homebrew Website", systemImage: "safari")
                            }
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding()
                    .background(Color.orange.opacity(0.1))
                    .cornerRadius(8)
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(8)
        }
    }
    
    // MARK: - rsync Status Helpers
    
    private func installStep(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
    
    private func checkRsyncStatus() {
        // Create a temporary BackupManager just to check rsync
        let tempContainer = try? ModelContainer(for: BackupSettings.self)
        guard let container = tempContainer else {
            rsyncStatus = .unknown
            return
        }
        
        let tempLogManager = LogManager(modelContainer: container)
        let tempManager = BackupManager(modelContainer: container, logManager: tempLogManager)
        
        if let rsyncPath = tempManager.realRsyncPath {
            rsyncStatus = .installed
            rsyncVersion = tempManager.getRsyncVersion()
        } else {
            // Check if openrsync exists
            if FileManager.default.fileExists(atPath: "/usr/bin/rsync") {
                rsyncStatus = .openRsync
                rsyncVersion = "macOS openrsync (not compatible)"
            } else {
                rsyncStatus = .notInstalled
                rsyncVersion = nil
            }
        }
    }
    
    private func openInstallInstructions() {
        if let url = URL(string: "https://brew.sh/") {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func openTerminal() {
        NSWorkspace.shared.launchApplication("Terminal")
    }
    
    private func copyInstallCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("brew install rsync", forType: .string)
        
        // Show brief confirmation
        testResult = "✅ Command copied to clipboard"
        
        // Clear after 2 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            if testResult.contains("clipboard") {
                testResult = ""
            }
        }
    }
    
    private func debugToolItem(_ title: String, _ description: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
            Spacer()
            Text(description)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.trailing)
        }
    }
    
    private func infoRow(label: String, value: String, color: Color = .primary) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
                .foregroundColor(color)
        }
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

// MARK: - rsync Status Enum

enum RsyncStatus {
    case unknown
    case installed
    case notInstalled
    case openRsync
    
    var icon: String {
        switch self {
        case .unknown: return "questionmark.circle"
        case .installed: return "checkmark.circle.fill"
        case .notInstalled: return "xmark.circle.fill"
        case .openRsync: return "exclamationmark.triangle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .unknown: return .gray
        case .installed: return .green
        case .notInstalled: return .red
        case .openRsync: return .orange
        }
    }
    
    var message: String {
        switch self {
        case .unknown: return "Checking..."
        case .installed: return "Real GNU rsync is installed"
        case .notInstalled: return "rsync is not installed"
        case .openRsync: return "Only macOS openrsync found (not compatible)"
        }
    }
    
    var backgroundColor: Color {
        switch self {
        case .unknown: return Color.gray.opacity(0.1)
        case .installed: return Color.green.opacity(0.1)
        case .notInstalled: return Color.red.opacity(0.1)
        case .openRsync: return Color.orange.opacity(0.1)
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
