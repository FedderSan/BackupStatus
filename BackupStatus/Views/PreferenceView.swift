import SwiftUI
import SwiftData

@MainActor
struct PreferencesView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var settings: BackupSettings?
    @State private var selectedTab = 0
    
    // Form fields
    @State private var backupInterval = 1
    
    // Login state items
    @State private var launchAtLogin = false
    @State private var autoStartError = ""
    
    // Retention settings
    @State private var logRetentionPeriod: LogRetentionPeriod = .days30
    
    // Debug Mode
    @AppStorage("debugModeEnabled") private var debugModeEnabled = false
    
    // rsync status
    @State private var rsyncStatus: RsyncStatus = .unknown
    @State private var rsyncVersion: String?
    
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
                
                dataManagementTab
                    .tabItem {
                        Label("Data", systemImage: "archivebox")
                    }
                    .tag(1)
                
                advancedTab
                    .tabItem {
                        Label("Advanced", systemImage: "wrench.and.screwdriver")
                    }
                    .tag(2)
            }
            .padding()
            
            Divider()
            
            // Footer with actions
            footerView
        }
        .frame(minWidth: 700, idealWidth: 800, maxWidth: 1200,
               minHeight: 500, idealHeight: 600, maxHeight: 900)
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
                    Text("Settings")
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
                
                Text("Configure backup profiles in the Profiles window")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
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
    
    // MARK: - General Tab
    
    private var generalTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Info Card
                HStack(spacing: 12) {
                    Image(systemName: "info.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Backup Configuration Moved")
                            .fontWeight(.semibold)
                        Text("Source and destination settings are now managed in the Profiles window. Open 'Manage Profiles' from the menu to configure your backups.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(12)
                
                // Backup Configuration
                VStack(alignment: .leading, spacing: 16) {
                    sectionHeader("Global Backup Settings", icon: "clock.arrow.circlepath")
                    
                    VStack(alignment: .leading, spacing: 16) {
                        // Backup Interval
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("Default Backup Interval")
                                    .frame(width: 180, alignment: .leading)
                                    .foregroundColor(.secondary)
                                
                                TextField("Hours", value: $backupInterval, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 80)
                                
                                Text("hours")
                                    .foregroundColor(.secondary)
                                
                                Spacer()
                            }
                            
                            Text("Default interval for new backup profiles. Individual profiles can override this setting.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 180)
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
                
                // Info about profile-specific settings
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: "info.circle.fill")
                            .font(.title3)
                            .foregroundColor(.blue)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Profile-Specific Retention")
                                .fontWeight(.semibold)
                            Text("Backup version retention is now configured per profile. Open 'Manage Profiles' to set retention policies for individual backups.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                }
                
                Spacer()
            }
            .padding()
        }
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
    
    // MARK: - Footer
    
    private var footerView: some View {
        HStack(spacing: 12) {
            Spacer()
            
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
    
    // MARK: - Helper Methods
    
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
    
    private func loadSettings() {
        let descriptor = FetchDescriptor<BackupSettings>()
        if let existingSettings = try? modelContext.fetch(descriptor).first {
            settings = existingSettings
            populateFields(from: existingSettings)
        } else {
            let newSettings = BackupSettings()
            modelContext.insert(newSettings)
            settings = newSettings
            populateFields(from: newSettings)
        }
    }
    
    private func populateFields(from settings: BackupSettings) {
        backupInterval = settings.backupIntervalHours
        logRetentionPeriod = settings.logRetentionPeriod
    }
    
    private func resetToDefaults() {
        let defaults = BackupSettings()
        populateFields(from: defaults)
    }
    
    private func saveSettings() {
        guard let settings = settings else { return }
        
        isSaving = true
        
        Task {
            settings.backupIntervalHours = backupInterval
            settings.logRetentionPeriod = logRetentionPeriod
            
            do {
                try modelContext.save()
                await MainActor.run {
                    isSaving = false
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                }
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
