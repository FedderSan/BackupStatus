import SwiftUI
import UniformTypeIdentifiers

struct LogView: View {
    @ObservedObject var logManager: LogManager
    @State private var selectedLevel: LogLevel? = nil
    @State private var searchText = ""
    @State private var isExporting = false
    @State private var showingExportPanel = false
    
    private var filteredLogs: [LogEntry] {
        var filtered = logManager.logs
        
        // Filter by level if selected
        if let selectedLevel = selectedLevel {
            filtered = filtered.filter { $0.level == selectedLevel }
        }
        
        // Filter by search text
        if !searchText.isEmpty {
            filtered = filtered.filter {
                $0.message.localizedCaseInsensitiveContains(searchText)
            }
        }
        
        return filtered.reversed() // Show newest first
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with controls
            HStack {
                Text("Backup Logs")
                    .font(.title2)
                    .fontWeight(.bold)
                
                Spacer()
                
                // Level filter
                Picker("Filter Level", selection: $selectedLevel) {
                    Text("All Levels").tag(LogLevel?.none)
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        HStack {
                            Image(systemName: level.systemImage)
                            Text(level.displayName)
                        }
                        .tag(LogLevel?.some(level))
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
                
                Button("Export") {
                    showingExportPanel = true
                }
                
                Button("Clear") {
                    logManager.clearLogs()
                }
                .foregroundColor(.red)
            }
            .padding()
            
            // Search bar
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("Search logs...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                
                if !searchText.isEmpty {
                    Button("Clear") {
                        searchText = ""
                    }
                    .foregroundColor(.secondary)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 8)
            
            Divider()
            
            // Logs list
            if filteredLogs.isEmpty {
                VStack {
                    Image(systemName: "doc.text")
                        .font(.largeTitle)
                        .foregroundColor(.secondary)
                    Text(logManager.logs.isEmpty ? "No logs yet" : "No logs match your filters")
                        .foregroundColor(.secondary)
                        .padding()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredLogs) { entry in
                    LogEntryView(entry: entry)
                }
                .listStyle(.plain)
            }
            
            // Status bar
            HStack {
                Text("\(filteredLogs.count) of \(logManager.logs.count) entries")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                Text("Live updating")
                    .font(.caption)
                    .foregroundColor(.green)
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .fileExporter(
            isPresented: $showingExportPanel,
            document: LogDocument(entries: logManager.logs),
            contentType: .plainText,
            defaultFilename: "backup-logs-\(Date().formatted(date: .numeric, time: .omitted)).txt"
        ) { result in
            switch result {
            case .success(let url):
                print("Logs exported to: \(url)")
            case .failure(let error):
                print("Export failed: \(error)")
            }
        }
    }
}

struct LogEntryView: View {
    let entry: LogEntry
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }
    
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Timestamp
            Text(timeFormatter.string(from: entry.timestamp))
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            
            // Level indicator
            HStack(spacing: 4) {
                Image(systemName: entry.level.systemImage)
                    .foregroundColor(entry.level.color)
                Text(entry.level.displayName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundColor(entry.level.color)
            }
            .frame(width: 60, alignment: .leading)
            
            // Message
            Text(entry.message)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 2)
        .contextMenu {
            Button("Copy Message") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(entry.message, forType: .string)
            }
            
            Button("Copy Full Entry") {
                let fullEntry = "[\(entry.timestamp)] [\(entry.level.displayName)] \(entry.message)"
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(fullEntry, forType: .string)
            }
        }
    }
}

// Document type for exporting logs
struct LogDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    
    var entries: [LogEntry]
    
    init(entries: [LogEntry]) {
        self.entries = entries
    }
    
    init(configuration: ReadConfiguration) throws {
        // Not used for export
        self.entries = []
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .medium
        
        let content = entries.map { entry in
            "[\(formatter.string(from: entry.timestamp))] [\(entry.level.displayName)] \(entry.message)"
        }.joined(separator: "\n")
        
        return FileWrapper(regularFileWithContents: content.data(using: .utf8) ?? Data())
    }
}

// Extension removed - systemImage already defined in LogManagerModel
