#if DEBUG
    import Combine
    import DebugDrawer
    import Foundation
    import OSLogClient
    import SwiftUI

    // MARK: - Log line model

    public struct LogLine: Identifiable {
        public let id = UUID()
        public let timestamp: Date
        public let text: String
        public let source: Source
        public let level: Level

        public enum Source: String, Sendable {
            case stdout, stderr, oslog
        }

        public enum Level: Comparable, Sendable {
            case debug, info, notice, error, fault

            /// The issue glyph a line of this level carries: an error for an error or a fault, none
            /// otherwise. os_log has no warning level (`Logger.warning` logs at the error level),
            /// so no level draws the warning glyph.
            var severity: DebugDrawerIssueGlyph.Severity? {
                switch self {
                case .error, .fault: .error
                case .debug, .info, .notice: nil
                }
            }

            var label: String? {
                switch self {
                case .error: "ERR"
                case .fault: "FLT"
                case .debug: "DBG"
                default: nil
                }
            }
        }
    }

    // MARK: - OSLogClient driver

    /// Receives os_log entries and pushes them into the shared ConsoleLogStore.
    final class ConsoleLogDriver: LogDriver, @unchecked Sendable {
        convenience init() {
            self.init(id: "com.debugdrawer.console")
        }

        #if os(macOS)
            override func processLog(
                level: LogLevel,
                subsystem: String,
                category: String,
                date: Date,
                message: String,
                components _: [OSLogMessageComponent]
            ) {
                handleLog(level: level, subsystem: subsystem, category: category, date: date, message: message)
            }
        #else
            override func processLog(
                level: LogLevel,
                subsystem: String,
                category: String,
                date: Date,
                message: String
            ) {
                handleLog(level: level, subsystem: subsystem, category: category, date: date, message: message)
            }
        #endif

        private func handleLog(level: LogLevel, subsystem: String, category: String, date: Date, message: String) {
            let mapped: LogLine.Level = switch level {
            case .debug: .debug
            case .info: .info
            case .notice: .notice
            case .error: .error
            case .fault: .fault
            case .undefined: .info
            }

            let prefix = subsystem.isEmpty ? "" : "[\(subsystem)/\(category)] "
            let line = LogLine(
                timestamp: date,
                text: "\(prefix)\(message)",
                source: .oslog,
                level: mapped
            )

            Task { @MainActor in
                ConsoleLogStore.shared.ingest(line)
            }
        }
    }

    // MARK: - Log store

    /// Captures stdout, stderr, and os_log output into a ring buffer.
    @MainActor
    public final class ConsoleLogStore: ObservableObject {
        public static let shared = ConsoleLogStore()

        @Published public private(set) var lines: [LogLine] = []
        @Published public var filterLevel: LogLine.Level = .debug

        /// Maximum number of lines retained in the ring buffer.
        public var capacity = 2000

        public var filteredLines: [LogLine] {
            lines.filter { $0.level >= filterLevel }
        }

        private var installed = false
        private let driver = ConsoleLogDriver()
        /// Original stdout fd, used to write diagnostics without triggering capture loop.
        private var originalStdoutFd: Int32 = -1
        /// Subject that receives individual log lines, throttled before publishing to `lines`.
        private let lineSubject = PassthroughSubject<LogLine, Never>()
        private var cancellable: AnyCancellable?

        private init() {
            cancellable = lineSubject
                .collect(.byTime(DispatchQueue.main, .milliseconds(100)))
                .receive(on: DispatchQueue.main)
                .sink { [weak self] batch in
                    guard let self, !batch.isEmpty else { return }
                    self.lines.append(contentsOf: batch)
                    if self.lines.count > self.capacity {
                        self.lines.removeFirst(self.lines.count - self.capacity)
                    }
                }
        }

        // MARK: - Installation

        /// Redirect stdout/stderr and start polling os_log.
        /// Call once at app startup. Safe to call multiple times (no-ops after first).
        public func install() {
            guard !installed else { return }
            installed = true

            // Only redirect stdout/stderr on macOS.
            // On iOS, dup2 on stdout breaks Xcode's debugger attachment.
            #if os(macOS)
                originalStdoutFd = dup(STDOUT_FILENO)
                redirectStream(source: .stdout, fd: STDOUT_FILENO)
                redirectStream(source: .stderr, fd: STDERR_FILENO)
            #endif

            Task {
                do {
                    let store = try OSLogStore(scope: .currentProcessIdentifier)
                    try await OSLogClient.initialize(pollingInterval: .custom(2), logStore: store)
                    await OSLogClient.registerDriver(driver)
                    await OSLogClient.startPolling()
                } catch {
                    logDirect("[DebugDrawer] OSLogClient init failed: \(error)\n")
                }
            }
        }

        /// Write directly to the original stdout fd, bypassing the pipe capture.
        private func logDirect(_ msg: String) {
            guard originalStdoutFd >= 0 else { return }
            msg.withCString { ptr in
                _ = write(originalStdoutFd, ptr, strlen(ptr))
            }
        }

        /// Push a line into the throttled pipeline.
        func ingest(_ line: LogLine) {
            lineSubject.send(line)
        }

        private func redirectStream(source: LogLine.Source, fd: Int32) {
            let pipe = Pipe()
            let originalFd = dup(fd)
            dup2(pipe.fileHandleForWriting.fileDescriptor, fd)

            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty else { return }
                // Forward to original destination.
                if originalFd >= 0 {
                    data.withUnsafeBytes { buf in
                        if let ptr = buf.baseAddress {
                            _ = write(originalFd, ptr, data.count)
                        }
                    }
                }
                guard let text = String(data: data, encoding: .utf8) else { return }
                let logLines = text.components(separatedBy: "\n")
                    .filter { !$0.isEmpty }
                    .map { LogLine(timestamp: Date(), text: $0, source: source, level: source == .stderr ? .error : .info) }

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    for line in logLines {
                        self.ingest(line)
                    }
                }
            }
        }

        public func clear() {
            lines.removeAll()
        }
    }

    // MARK: - Plugin

    public struct ConsolePlugin: DebugDrawerPlugin {
        public var title = "Console"
        public var category = "Logs & Network"
        public var icon = "terminal"

        public init() {}

        public var body: some View {
            ConsolePluginView()
        }

        /// How many lines the console holds.
        public var headerAccessory: some View {
            ConsoleHeaderAccessoryView()
        }
    }

    /// The Console plugin's header accessory, read from the shared store as the plugin's body
    /// reads it.
    struct ConsoleHeaderAccessoryView: View {
        @ObservedObject private var store = ConsoleLogStore.shared

        var body: some View {
            ConsoleHeaderSummary(lineCount: store.lines.count)
        }
    }

    /// How many lines the console holds ("1,204 lines").
    struct ConsoleHeaderSummary: View {
        let lineCount: Int

        /// The count as the header shows it.
        var text: String {
            lineCount == 1 ? "1 line" : "\(lineCount.formatted()) lines"
        }

        var body: some View {
            Text(text)
        }
    }

    // MARK: - Console view (proper SwiftUI View so @ObservedObject works)

    struct ConsolePluginView: View {
        @ObservedObject private var store = ConsoleLogStore.shared
        @State private var isFollowing = true
        @State private var searchText = ""

        private var visibleLines: [LogLine] {
            let filtered = store.filteredLines
            guard !searchText.isEmpty else { return filtered }
            let query = searchText.lowercased()
            return filtered.filter { $0.text.lowercased().contains(query) }
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                TextField("Search logs...", text: $searchText)
                    .debugDrawerTextFieldStyle()
                    .accessibilityLabel("Search logs")

                // Toolbar — filter picker is in its own view to avoid
                // re-creating the NSSegmentedControl on every log batch.
                ConsoleToolbarView(
                    isFollowing: $isFollowing,
                    filterLevel: $store.filterLevel,
                    copyAll: { debugDrawerCopyToClipboard(visibleLines.copiedText) },
                    clear: { store.clear() }
                )

                DebugDrawerCodeBlock {
                    ConsoleTextView(
                        lines: visibleLines,
                        isFollowing: $isFollowing
                    )
                    .frame(minHeight: 120, maxHeight: 300)
                }
            }
        }
    }

    /// Extracted toolbar so the segmented picker doesn't get rebuilt on every log update.
    /// Only `isFollowing` changes frequently — the picker binding (`filterLevel`) is stable and
    /// won't cause the NSSegmentedControl to be recreated. The line count is the header's
    /// accessory, so the toolbar doesn't repeat it.
    struct ConsoleToolbarView: View {
        @Binding var isFollowing: Bool
        @Binding var filterLevel: LogLine.Level
        let copyAll: () -> Void
        let clear: () -> Void

        var body: some View {
            // The action row wraps what doesn't fit one line, and stacks at accessibility sizes.
            DebugDrawerActionRow {
                ConsoleFilterPicker(filterLevel: $filterLevel)

                if !isFollowing {
                    Button("Resume") { isFollowing = true }
                        .debugDrawerButtonStyle(.borderless)
                        .accessibilityHint("Scrolls to the newest line and follows new ones")
                }

                Button("Copy All", action: copyAll)
            } trailing: {
                Button("Clear", role: .destructive, action: clear)
                    .debugDrawerButtonStyle(.destructive)
                    .accessibilityLabel("Clear the console")
            }
        }
    }

    /// The segmented picker in its own view to prevent SwiftUI from
    /// recreating the NSSegmentedControl when the parent re-renders.
    struct ConsoleFilterPicker: View {
        @Binding var filterLevel: LogLine.Level

        var body: some View {
            Picker("Level", selection: $filterLevel) {
                Text("All").tag(LogLine.Level.debug)
                Text("Info+").tag(LogLine.Level.info)
                Text("Errors").tag(LogLine.Level.error)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Lowest level shown")
            .accessibilityElement(children: .contain)
            .fixedSize()
        }
    }

    // MARK: - Convenience installer

    public extension DebugDrawer {
        /// Install the console capture plugin. Call once at app startup.
        /// Captures stdout, stderr, and os_log entries.
        func installConsole() {
            ConsoleLogStore.shared.install()
            registerGlobal(ConsolePlugin())
        }
    }
#endif
