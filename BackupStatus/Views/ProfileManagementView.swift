//
//  ProfileManagementView 2.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 28/10/2025.
//


//
//  ProfileManagementView.swift
//  BackupStatus
//
//  Complete profile management with WebDAV support
//

import SwiftUI
import SwiftData

struct ProfileManagementView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BackupProfile.name) private var profiles: [BackupProfile]
    
    @State private var selectedProfile: BackupProfile?
    @State private var showingAddProfile = false
    
    var body: some View {
        NavigationSplitView {
            // Profile List
            List(selection: $selectedProfile) {
                ForEach(profiles) { profile in
                    ProfileListItem(profile: profile)
                        .tag(profile)
                }
            }
            .navigationTitle("Backup Profiles")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button(action: { showingAddProfile = true }) {
                        Label("Add Profile", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddProfile) {
                AddProfileSheet(modelContext: modelContext)
            }
        } detail: {
            if let profile = selectedProfile {
                ProfileDetailView(profile: profile, modelContext: modelContext)
            } else {
                ContentUnavailableView(
                    "Select a Profile",
                    systemImage: "folder.badge.gearshape",
                    description: Text("Choose a profile from the list or create a new one")
                )
            }
        }
    }
}

// MARK: - Profile List Item

struct ProfileListItem: View {
    @Bindable var profile: BackupProfile
    
    var body: some View {
        HStack(spacing: 12) {
            // Icon based on remote type
            Image(systemName: profile.remoteType.icon)
                .font(.title3)
                .foregroundColor(profile.isEnabled ? .blue : .gray)
                .frame(width: 32)
            
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(profile.name)
                        .fontWeight(.medium)
                    
                    if !profile.isEnabled {
                        Text("Disabled")
                            .font(.caption2)
                            .foregroundColor(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.gray)
                            .cornerRadius(4)
                    }
                }
                
                HStack(spacing: 4) {
                    Text(profile.profileType.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Text(profile.remoteType.displayName)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                if let lastBackup = profile.lastSuccessfulBackup {
                    Text("Last: \(lastBackup, style: .relative) ago")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Toggle("", isOn: $profile.isEnabled)
                .labelsHidden()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Add Profile Sheet

struct AddProfileSheet: View {
    let modelContext: ModelContext
    @Environment(\.dismiss) private var dismiss
    
    @State private var profileName = ""
    @State private var profileType: BackupProfileType = .versioned
    @State private var remoteType: ProfileRemoteType = .local
    
    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 8) {
                Image(systemName: "folder.badge.plus")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
                
                Text("Create Backup Profile")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            .padding(.top)
            
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Profile Name")
                        .fontWeight(.semibold)
                    TextField("e.g., Documents Backup", text: $profileName)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Destination Type")
                        .fontWeight(.semibold)
                    
                    ForEach(ProfileRemoteType.allCases, id: \.self) { type in
                        RemoteTypeCard(
                            type: type,
                            isSelected: remoteType == type,
                            action: { remoteType = type }
                        )
                    }
                }
                
                VStack(alignment: .leading, spacing: 12) {
                    Text("Backup Type")
                        .fontWeight(.semibold)
                    
                    ForEach(BackupProfileType.allCases, id: \.self) { type in
                        ProfileTypeCard(
                            type: type,
                            isSelected: profileType == type,
                            action: { profileType = type }
                        )
                    }
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            
            Spacer()
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button("Create Profile") {
                    createProfile()
                }
                .buttonStyle(.borderedProminent)
                .disabled(profileName.isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 550, height: 650)
    }
    
    private func createProfile() {
        let profile = BackupProfile(name: profileName, profileType: profileType, remoteType: remoteType)
        modelContext.insert(profile)
        try? modelContext.save()
        dismiss()
    }
}

// MARK: - Remote Type Card

struct RemoteTypeCard: View {
    let type: ProfileRemoteType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: type.icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .frame(width: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(type.displayName)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(type.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Profile Type Card

struct ProfileTypeCard: View {
    let type: BackupProfileType
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: type.icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .blue : .secondary)
                    .frame(width: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(type.displayName)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                    
                    Text(type.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.1) : Color.clear)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Profile Detail View

struct ProfileDetailView: View {
    @Bindable var profile: BackupProfile
    let modelContext: ModelContext
    @State private var showingDeleteConfirmation = false
    @State private var showingPasswordSheet = false
    @State private var testConnectionStatus: TestConnectionStatus = .idle
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                profileHeader
                Divider()
                basicSettingsSection
                sourceSection
                
                // Destination section changes based on remote type
                if profile.remoteType == .local {
                    localDestinationSection
                } else {
                    webdavDestinationSection
                }
                
                if profile.profileType == .versioned {
                    versionedSettingsSection
                } else {
                    oneWaySyncSettingsSection
                }
                
                statisticsSection
                Spacer()
            }
            .padding()
        }
        .navigationTitle(profile.name)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Delete Profile") {
                    showingDeleteConfirmation = true
                }
                .foregroundColor(.red)
            }
        }
        .alert("Delete Profile?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                modelContext.delete(profile)
                try? modelContext.save()
            }
        } message: {
            Text("This will permanently delete \"\(profile.name)\". Backup data will not be deleted.")
        }
        .sheet(isPresented: $showingPasswordSheet) {
            WebDAVPasswordSheet(profile: profile)
        }
    }
    
    private var profileHeader: some View {
        HStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(profile.remoteType == .webdav ? Color.blue.opacity(0.2) : Color.gray.opacity(0.2))
                    .frame(width: 80, height: 80)
                
                Image(systemName: profile.remoteType.icon)
                    .font(.system(size: 36))
                    .foregroundColor(profile.remoteType == .webdav ? .blue : .gray)
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.title)
                    .fontWeight(.bold)
                
                HStack(spacing: 8) {
                    Text(profile.profileType.displayName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text("•")
                        .foregroundColor(.secondary)
                    
                    Text(profile.remoteType.displayName)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Toggle("Enabled", isOn: $profile.isEnabled)
                    .toggleStyle(.switch)
            }
        }
    }
    
    private var basicSettingsSection: some View {
        GroupBox("Basic Settings") {
            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Profile Name") {
                    TextField("Name", text: $profile.name)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 300)
                }
                
                LabeledContent("Backup Interval") {
                    HStack {
                        TextField("Hours", value: $profile.backupIntervalHours, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                        Text("hours")
                            .foregroundColor(.secondary)
                    }
                }
            }
            .padding()
        }
    }
    
    private var sourceSection: some View {
        GroupBox("Source Configuration") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Source Folder")
                        .fontWeight(.semibold)
                    
                    HStack {
                        TextField("Choose folder", text: $profile.sourcePath)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Browse") {
                            chooseSourcePath()
                        }
                    }
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Exclude Patterns")
                        .fontWeight(.semibold)
                    
                    TextField("e.g., .DS_Store, *.tmp", text: $profile.excludePatterns)
                        .textFieldStyle(.roundedBorder)
                    
                    Text("Comma-separated patterns to exclude from backup")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }
    
    private var localDestinationSection: some View {
        GroupBox("Local Destination") {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Destination Folder")
                        .fontWeight(.semibold)
                    
                    HStack {
                        TextField("Choose folder", text: $profile.destinationPath)
                            .textFieldStyle(.roundedBorder)
                        
                        Button("Browse") {
                            chooseDestinationPath()
                        }
                    }
                }
            }
            .padding()
        }
    }
    
    private var webdavDestinationSection: some View {
        GroupBox("WebDAV Configuration") {
            VStack(alignment: .leading, spacing: 16) {
                // Server Settings
                VStack(alignment: .leading, spacing: 12) {
                    Text("Server Settings")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    LabeledContent("Server Host") {
                        TextField("e.g., cloud.example.com", text: $profile.webdavServerHost)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)
                    }
                    
                    HStack {
                        LabeledContent("Port") {
                            TextField("Port", value: $profile.webdavServerPort, format: .number)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 80)
                        }
                        
                        Spacer()
                        
                        Toggle("Use HTTPS", isOn: $profile.webdavUseHTTPS)
                        
                        Spacer()
                        
                        Toggle("Verify SSL", isOn: $profile.webdavVerifySSL)
                    }
                }
                
                Divider()
                
                // Path Settings
                VStack(alignment: .leading, spacing: 12) {
                    Text("Path Settings")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    LabeledContent("Base URL Path") {
                        TextField("/remote.php/dav/files/username", text: $profile.webdavURL)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)
                    }
                    
                    LabeledContent("Backup Folder") {
                        TextField("Backups", text: $profile.webdavPath)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)
                    }
                    
                    Text("Full URL: \(profile.fullWebDAVURL)/\(profile.webdavPath)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                }
                
                Divider()
                
                // Authentication
                VStack(alignment: .leading, spacing: 12) {
                    Text("Authentication")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    
                    LabeledContent("Username") {
                        TextField("Username", text: $profile.webdavUsername)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: 300)
                    }
                    
                    HStack {
                        LabeledContent("Password") {
                            HStack {
                                if profile.webdavPasswordObscured.isEmpty {
                                    Text("Not set")
                                        .foregroundColor(.secondary)
                                } else {
                                    Text("••••••••")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        
                        Button(profile.webdavPasswordObscured.isEmpty ? "Set Password" : "Change Password") {
                            showingPasswordSheet = true
                        }
                    }
                }
                
                Divider()
                
                // Connection Test
                HStack {
                    Button(action: testWebDAVConnection) {
                        HStack {
                            if testConnectionStatus == .testing {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                            Image(systemName: testConnectionStatus.icon)
                            Text(testConnectionStatus.text)
                        }
                    }
                    .disabled(testConnectionStatus == .testing || profile.webdavServerHost.isEmpty || profile.webdavUsername.isEmpty || profile.webdavPasswordObscured.isEmpty)
                    
                    Spacer()
                    
                    if testConnectionStatus == .success {
                        Text("Connection successful!")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else if testConnectionStatus == .failed {
                        Text("Connection failed")
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
            }
            .padding()
        }
    }
    
    private var versionedSettingsSection: some View {
        GroupBox("Version Settings") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Create Version Snapshots", isOn: $profile.createVersions)
                
                if profile.createVersions {
                    LabeledContent("Keep Versions") {
                        Picker("", selection: $profile.versionRetentionCount) {
                            ForEach(BackupVersionRetention.allCases, id: \.rawValue) { retention in
                                Text(retention.displayName).tag(retention.rawValue)
                            }
                        }
                        .pickerStyle(.menu)
                        .frame(width: 150)
                    }
                    
                    Text(profile.versionRetention.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
        }
    }
    
    private var oneWaySyncSettingsSection: some View {
        GroupBox("Sync Settings") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Use Trash Folder for Deletions", isOn: $profile.useTrashFolder)
                
                if profile.remoteType == .webdav && profile.useTrashFolder {
                    Text("⚠️ WebDAV trash folder not yet implemented")
                        .font(.caption)
                        .foregroundColor(.orange)
                        .padding(.leading)
                }
                
                if profile.useTrashFolder && profile.remoteType == .local {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Trash Folder Name") {
                            TextField(".backup_trash", text: $profile.trashFolderName)
                                .textFieldStyle(.roundedBorder)
                                .frame(maxWidth: 200)
                        }
                        
                        Toggle("Auto-Empty Trash", isOn: $profile.autoEmptyTrash)
                        
                        if profile.autoEmptyTrash {
                            LabeledContent("Keep Trash For") {
                                HStack {
                                    TextField("Days", value: $profile.trashRetentionDays, format: .number)
                                        .textFieldStyle(.roundedBorder)
                                        .frame(width: 80)
                                    Text("days")
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                    .padding(.leading)
                }
            }
            .padding()
        }
    }
    
    private var statisticsSection: some View {
        GroupBox("Statistics") {
            VStack(alignment: .leading, spacing: 8) {
                LabeledContent("Total Backups Run") {
                    Text("\(profile.totalBackupsRun)")
                        .fontWeight(.medium)
                }
                
                if let lastBackup = profile.lastSuccessfulBackup {
                    LabeledContent("Last Successful Backup") {
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(lastBackup, style: .relative)
                                .fontWeight(.medium)
                            Text(lastBackup, style: .date)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                if profile.lastBackupFilesCount > 0 {
                    LabeledContent("Last Backup") {
                        Text("\(profile.lastBackupFilesCount) files, \(ByteCountFormatter.string(fromByteCount: profile.lastBackupSize, countStyle: .file))")
                            .fontWeight(.medium)
                    }
                }
            }
            .padding()
        }
    }
    
    // MARK: - Actions
    
    private func chooseSourcePath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose source folder to backup"
        
        if panel.runModal() == .OK, let url = panel.url {
            profile.sourcePath = url.path
        }
    }
    
    private func chooseDestinationPath() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.message = "Choose backup destination folder"
        
        if panel.runModal() == .OK, let url = panel.url {
            profile.destinationPath = url.path
        }
    }
    
    private func testWebDAVConnection() {
        testConnectionStatus = .testing
        
        Task {
            // Simple curl test
            guard let plainPassword = await profile.getPlainPassword() else {
                await MainActor.run {
                    testConnectionStatus = .failed
                }
                return
            }
            
            let result = await testWebDAVWithCurl(
                url: profile.fullWebDAVURL,
                username: profile.webdavUsername,
                password: plainPassword,
                verifySSL: profile.webdavVerifySSL
            )
            
            await MainActor.run {
                testConnectionStatus = result ? .success : .failed
            }
        }
    }
    
    private func testWebDAVWithCurl(url: String, username: String, password: String, verifySSL: Bool) async -> Bool {
        return await withCheckedContinuation { continuation in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/curl")
            
            var arguments = [
                "-s", "-f", "-X", "PROPFIND",
                "--user", "\(username):\(password)",
                "-H", "Content-Type: text/xml",
                "-H", "Depth: 0",
                "--max-time", "10"
            ]
            
            if !verifySSL {
                arguments.append("-k")
            }
            
            arguments.append(url)
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

// MARK: - WebDAV Password Sheet

struct WebDAVPasswordSheet: View {
    @Bindable var profile: BackupProfile
    @Environment(\.dismiss) private var dismiss
    
    @State private var password = ""
    @State private var confirmPassword = ""
    @State private var isSaving = false
    
    var passwordsMatch: Bool {
        return password == confirmPassword && !password.isEmpty
    }
    
    var body: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.blue)
                
                Text("Set WebDAV Password")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            .padding(.top)
            
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Password")
                        .fontWeight(.semibold)
                    
                    SecureField("Enter password", text: $password)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Confirm Password")
                        .fontWeight(.semibold)
                    
                    SecureField("Confirm password", text: $confirmPassword)
                        .textFieldStyle(.roundedBorder)
                }
                
                if !password.isEmpty && !confirmPassword.isEmpty && !passwordsMatch {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundColor(.orange)
                        Text("Passwords do not match")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "info.circle")
                            .foregroundColor(.blue)
                        Text("Password Security")
                            .font(.caption)
                            .fontWeight(.semibold)
                    }
                    
                    Text("Your password will be encrypted using rclone's obscure function before being stored.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(12)
            
            Spacer()
            
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                
                Spacer()
                
                Button(action: savePassword) {
                    HStack {
                        if isSaving {
                            ProgressView()
                                .scaleEffect(0.7)
                        }
                        Text("Save Password")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!passwordsMatch || isSaving)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 450, height: 450)
    }
    
    private func savePassword() {
        isSaving = true
        
        Task {
            await profile.setPassword(password)
            
            await MainActor.run {
                isSaving = false
                dismiss()
            }
        }
    }
}

// MARK: - Test Connection Status

enum TestConnectionStatus {
    case idle
    case testing
    case success
    case failed
    
    var icon: String {
        switch self {
        case .idle: return "network"
        case .testing: return "arrow.clockwise"
        case .success: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }
    
    var text: String {
        switch self {
        case .idle: return "Test Connection"
        case .testing: return "Testing..."
        case .success: return "Test Connection"
        case .failed: return "Test Again"
        }
    }
}

