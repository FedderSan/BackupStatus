//
//  LogView.swift
//  BackupStatus
//
//  Created by Daniel Feddersen on 26/07/2025.
//

import SwiftUI

struct LogView: View {
    @ObservedObject var logManager: LogManager
    @State private var selectedLogLevel: LogEntry.LogLevel? = nil
    @State private var searchText: String = ""
    @State private var autoScroll: Bool = true
    
    var filteredLogs: [LogEntry] {
        var logs = logManager.logEntries
        
        // Filter by log level
        if let selectedLevel = selectedLogLevel {
            logs = logs.filter { $0.level == selectedLevel }
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            logs = logs.filter { $0.message.localizedCaseInsensitiveContains(searchText) }
        }
        
        return logs
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                // Log level filter
                Picker("Log Level", selection: $selectedLogLevel) {
                    Text("All Levels").tag(nil as LogEntry.LogLevel?)
                    ForEach(LogEntry.LogLevel.allCases, id: \.self) { level in
                        HStack {
                            Image(systemName: level.icon)
                                .foregroundColor(level.color)
                            Text(level.rawValue)
                        }
                        .tag(level as LogEntry.LogLevel?)
                    }
                }
                .pickerStyle(MenuPickerStyle())
                .frame(width: 150)
                
                Spacer()
                
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search logs...", text: $searchText)
                        .textFieldStyle(RoundedBorderTextFieldStyle())
                }
                .frame(width: 200)
                
                Spacer()
                
                // Auto-scroll toggle
                Toggle("Auto-scroll", isOn: $autoScroll)
                    .toggleStyle(CheckboxToggleStyle())
                		
                // Clear logs button
                Button("Clear") {
                    logManager.clearLogs()
                }
                
                // Export logs button
                Button("Export") {
                    exportLogs()
                }
            }
            .padding()
            .background(Color(NSColor.controlBackgroundColor))
            
            Divider()
            
            // Log entries
            if filteredLogs.isEmpty {
                VStack {
                    Spacer()
                    Text("No log entries")
                        .foregroundColor(.secondary)
                        .font(.title2)
                    Spacer()
                }
            } else {
                ScrollViewReader { proxy in
                    List(filteredLogs) { entry in
                        LogEntryRow(entry: entry)
                    }
                    .listStyle(PlainListStyle())
                    .onChange(of: logManager.logEntries.count) { _ in
                        if autoScroll && !filteredLogs.isEmpty {
                            withAnimation(.easeOut(duration: 0.3)) {
                                proxy.scrollTo(filteredLogs.last?.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Backup Log")
        .frame(minWidth: 600, minHeight: 400)
    }
    
    private func exportLogs() {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.plainText]
        savePanel.nameFieldStringValue = "backup_log_\(Date().formatted(date: .abbreviated, time: .omitted)).txt"
        
        if savePanel.runModal() == .OK {
            guard let url = savePanel.url else { return }
            
            do {
                try logManager.exportLogs().write(to: url, atomically: true, encoding: .utf8)
            } catch {
                // Could show an alert here
                print("Failed to export logs: \(error)")
            }
        }
    }
}

struct LogEntryRow: View {
    let entry: LogEntry
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(entry.timestamp.formatted(date: .omitted, time: .standard))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            
            // Log level icon and badge
            HStack(spacing: 4) {
                Image(systemName: entry.level.icon)
                    .foregroundColor(entry.level.color)
                    .frame(width: 12)
                
                Text(entry.level.rawValue)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(entry.level.color)
                    .frame(width: 60, alignment: .leading)
            }
            
            // Message
            Text(entry.message)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
    }
}

struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack {
                Image(systemName: configuration.isOn ? "checkmark.square" : "square")
                    .foregroundColor(configuration.isOn ? .accentColor : .secondary)
                configuration.label
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}
