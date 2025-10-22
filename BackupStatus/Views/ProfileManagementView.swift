//
//  ProfileManagementView.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 22/10/2025.
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
            Image(systemName: profile.profileType.icon)
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
                
                Text(profile.profileType.displayName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
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
        .frame(width: 500, height: 500)
    }
    
    private func createProfile() {
        let profile = BackupProfile(name: profileName, profileType: profileType)
        modelContext.insert(profile)
        try? modelContext.save()
        dismiss()
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
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                profileHeader
                Divider()
                basicSettingsSection
                sourceSection
                destinationSection
                
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
    }
    
    private var profileHeader: some View {
        HStack(spacing: 16) {
            Image(systemName: profile.profileType.icon)
                .font(.system(size: 48))
                .foregroundColor(.blue)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(profile.name)
                    .font(.title)
                    .fontWeight(.bold)
                
                Text(profile.profileType.displayName)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
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
                }
            }
            .padding()
        }
    }
    
    private var destinationSection: some View {
        GroupBox("Destination Configuration") {
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
                }
            }
            .padding()
        }
    }
    
    private var oneWaySyncSettingsSection: some View {
        GroupBox("Sync Settings") {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Use Trash Folder for Deletions", isOn: $profile.useTrashFolder)
                
                if profile.useTrashFolder {
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
                        Text(lastBackup, style: .relative)
                            .fontWeight(.medium)
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
}
