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

            var color: Color {
                switch self {
                case .debug: .secondary
                case .info: .primary
                case .notice: .primary
                case .error: .red
                case .fault: .red
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
            VStack(alignment: .leading, spacing: 6) {
                // Search field
                TextField("Search logs...", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .controlSize(.small)
                    .accessibilityLabel("Search logs")

                // Toolbar — filter picker is in its own view to avoid
                // re-creating the NSSegmentedControl on every log batch.
                ConsoleToolbarView(
                    lineCount: visibleLines.count,
                    isFollowing: $isFollowing,
                    filterLevel: $store.filterLevel,
                    copyAll: { debugDrawerCopyToClipboard(visibleLines.copiedText) },
                    clear: { store.clear() }
                )

                ConsoleTextView(
                    lines: visibleLines,
                    isFollowing: $isFollowing
                )
                .frame(minHeight: 120, maxHeight: 300)
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    /// Extracted toolbar so the segmented picker doesn't get rebuilt on every log update.
    /// Only `lineCount` and `isFollowing` change frequently — the picker binding
    /// (`filterLevel`) is stable and won't cause the NSSegmentedControl to be recreated.
    struct ConsoleToolbarView: View {
        let lineCount: Int
        @Binding var isFollowing: Bool
        @Binding var filterLevel: LogLine.Level
        let copyAll: () -> Void
        let clear: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            // At accessibility sizes one row can't hold the count and every control, and squeezing
            // it breaks words, so the count takes its own line and the controls wrap below it.
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    summary
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 12) { controls }
                        VStack(alignment: .leading, spacing: 6) { controls }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    summary
                    Spacer()
                    controls
                }
            }
        }

        private var summary: some View {
            HStack(spacing: 8) {
                Text("\(lineCount) lines")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if !isFollowing {
                    Button("Resume") { isFollowing = true }
                        .font(.caption)
                        .buttonStyle(.plain)
                        .foregroundStyle(Color.accentColor)
                }
            }
        }

        @ViewBuilder private var controls: some View {
            ConsoleFilterPicker(filterLevel: $filterLevel)

            Button("Copy All", action: copyAll)
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

            Button("Clear", action: clear)
                .font(.caption)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
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
            .frame(width: 160)
            .controlSize(.mini)
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
