import SwiftUI
import UniformTypeIdentifiers

struct LogView: View {
    @ObservedObject var logManager: LogManager
    @State private var selectedLevel: LogLevel? = nil
    @State private var searchText = ""
    @State private var isExporting = false
    @State private var showingExportPanel = false
    @State private var exportAllLogs = false
    @State private var showingLogStats = false
    @State private var logStats: (total: Int, byLevel: [LogLevel: Int], oldestDate: Date?, newestDate: Date?) = (0, [:], nil, nil)
    @State private var exportDocument: LogDocument?
    
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
                
                // Statistics button (NEW)
                Button("Stats") {
                    Task {
                        logStats = await logManager.getLogStatistics()
                        showingLogStats = true
                    }
                }
                
                // Export menu (ENHANCED)
                Menu("Export") {
                    Button("Export Visible Logs") {
                        exportVisibleLogs()
                    }
                    
                    Button("Export All Logs from Database") {
                        exportAllLogsFromDatabase()
                    }
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
                    
                    // Show hint about persistent logs (NEW)
                    if logManager.logs.isEmpty {
                        VStack(spacing: 4) {
                            Text("Logs are automatically saved and will persist between app restarts")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                            
                            Text("Try running a backup or force backup to see logs appear")
                                .font(.caption)
                                .foregroundColor(.blue)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(filteredLogs) { entry in
                    LogEntryView(entry: entry)
                        .listRowSeparator(.hidden)
                }
                .listStyle(.plain)
            }
            
            // Enhanced status bar
            HStack {
                Text("\(filteredLogs.count) of \(logManager.logs.count) entries")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                // Live updating indicator with pulse animation
                HStack(spacing: 4) {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 6, height: 6)
                        .scaleEffect(1.0)
                        .animation(.easeInOut(duration: 1).repeatForever(autoreverses: true), value: UUID())
                        .onAppear {
                            // Trigger animation
                        }
                    Text("Live updating")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 4)
            .background(Color(NSColor.controlBackgroundColor))
        }
        .fileExporter(
            isPresented: $showingExportPanel,
            document: exportDocument ?? LogDocument(entries: []),
            contentType: .plainText,
            defaultFilename: "backup-logs-\(Date().formatted(date: .numeric, time: .omitted))\(exportAllLogs ? "-all" : "").txt"
        ) { result in
            switch result {
            case .success(let url):
                print("Logs exported to: \(url)")
            case .failure(let error):
                print("Export failed: \(error)")
            }
            exportDocument = nil // Clean up
        }
        .sheet(isPresented: $showingLogStats) {
            LogStatisticsView(stats: logStats, logManager: logManager)
        }
    }
    
    // MARK: - Export Methods
    
    private func exportVisibleLogs() {
        exportAllLogs = false
        exportDocument = LogDocument(entries: logManager.logs)
        showingExportPanel = true
    }
    
    private func exportAllLogsFromDatabase() {
        exportAllLogs = true
        isExporting = true
        
        Task { @MainActor in
            let allLogsContent = await logManager.exportAllLogsFromDatabase()
            exportDocument = LogDocument(content: allLogsContent)
            isExporting = false
            showingExportPanel = true
        }
    }
}

// MARK: - Enhanced Log Entry View
struct LogEntryView: View {
    let entry: LogEntry
    @State private var isExpanded = false
    
    private var timeFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .medium
        return formatter
    }
    
    private var fullDateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                // Timestamp
                Text(timeFormatter.string(from: entry.timestamp))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundColor(.secondary)
                    .frame(width: 80, alignment: .leading)
                
                // Level indicator with enhanced styling
                HStack(spacing: 4) {
                    Image(systemName: entry.level.systemImage)
                        .foregroundColor(entry.level.color)
                        .frame(width: 12)
                    Text(entry.level.displayName)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(entry.level.color)
                }
                .frame(width: 70, alignment: .leading)
                
                // Message with smart truncation
                VStack(alignment: .leading, spacing: 2) {
                    if entry.message.count > 150 && !isExpanded {
                        Text(String(entry.message.prefix(150)) + "...")
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        
                        Button("Show More") {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isExpanded = true
                            }
                        }
                        .font(.caption)
                        .foregroundColor(.blue)
                    } else {
                        Text(entry.message)
                            .font(.system(.body, design: .monospaced))
                            .textSelection(.enabled)
                        
                        if isExpanded {
                            Button("Show Less") {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isExpanded = false
                                }
                            }
                            .font(.caption)
                            .foregroundColor(.blue)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background(entry.level == .error ? Color.red.opacity(0.05) :
                       entry.level == .warning ? Color.orange.opacity(0.05) : Color.clear)
            .cornerRadius(4)
            .contextMenu {
                Button("Copy Message") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.message, forType: .string)
                }
                
                Button("Copy Full Entry") {
                    let fullEntry = "[\(fullDateFormatter.string(from: entry.timestamp))] [\(entry.level.displayName)] \(entry.message)"
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(fullEntry, forType: .string)
                }
                
                Button("Copy Timestamp") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(fullDateFormatter.string(from: entry.timestamp), forType: .string)
                }
            }
        }
    }
}

// MARK: - Log Statistics View (NEW)
struct LogStatisticsView: View {
    let stats: (total: Int, byLevel: [LogLevel: Int], oldestDate: Date?, newestDate: Date?)
    let logManager: LogManager
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Log Statistics")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button("Done") {
                    dismiss()
                }
            }
            
            GroupBox("Database Summary") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Total persisted logs:")
                        Spacer()
                        Text("\(stats.total)")
                            .fontWeight(.semibold)
                    }
                    
                    if let oldest = stats.oldestDate, let newest = stats.newestDate {
                        HStack(alignment: .top) {
                            Text("Date range:")
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(oldest.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                Text("to")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(newest.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                            }
                        }
                        
                        let daySpan = Calendar.current.dateComponents([.day], from: oldest, to: newest).day ?? 0
                        HStack {
                            Text("Span:")
                            Spacer()
                            Text("\(daySpan) days")
                                .fontWeight(.semibold)
                        }
                    }
                }
                .padding()
            }
            
            GroupBox("By Level") {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(LogLevel.allCases, id: \.self) { level in
                        let count = stats.byLevel[level] ?? 0
                        HStack {
                            HStack(spacing: 4) {
                                Image(systemName: level.systemImage)
                                    .foregroundColor(level.color)
                                Text(level.displayName)
                                    .foregroundColor(level.color)
                            }
                            
                            Spacer()
                            
                            Text("\(count)")
                                .fontWeight(.semibold)
                            
                            if stats.total > 0 {
                                Text("(\(Int((Double(count) / Double(stats.total)) * 100))%)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
                .padding()
            }
            
            GroupBox("Actions") {
                VStack(spacing: 8) {
                    Button("Force Clean Old Logs") {
                        Task {
                            await logManager.forceCleanOldLogs()
                            dismiss()
                        }
                    }
                    .foregroundColor(.orange)
                    
                    Text("This will remove logs older than the configured retention period")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
            }
            
            Spacer()
        }
        .padding()
        .frame(width: 400, height: 500)
    }
}

// MARK: - Updated Document Type
struct LogDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.plainText] }
    
    private var entries: [LogEntry]?
    private var content: String?
    
    init(entries: [LogEntry]) {
        self.entries = entries
        self.content = nil
    }
    
    init(content: String) {
        self.entries = nil
        self.content = content
    }
    
    init(configuration: ReadConfiguration) throws {
        // Not used for export
        self.entries = []
        self.content = nil
    }
    
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        let finalContent: String
        
        if let content = content {
            // Use pre-formatted content
            finalContent = content
        } else if let entries = entries {
            // Format entries
            let formatter = DateFormatter()
            formatter.dateStyle = .short
            formatter.timeStyle = .medium
            
            finalContent = entries.map { entry in
                "[\(formatter.string(from: entry.timestamp))] [\(entry.level.displayName)] \(entry.message)"
            }.joined(separator: "\n")
        } else {
            finalContent = ""
        }
        
        return FileWrapper(regularFileWithContents: finalContent.data(using: .utf8) ?? Data())
    }
}
