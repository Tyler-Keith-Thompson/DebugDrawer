#if DEBUG
    import Combine
    import DebugDrawer
    import Foundation
    import OSLogClient
    import SwiftUI

    // MARK: - Log line model

    public struct LogLine: Identifiable, Sendable {
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

        /// The lines the console shows at the level filter: the captured ones, or the earlier
        /// session's while `source` is `.previous`.
        var shownLines: [LogLine] {
            switch source {
            case .captured: filteredLines
            case .previous: (previousLog?.lines ?? []).filter { $0.level >= filterLevel }
            }
        }

        /// Whether the console shows the captured lines or an earlier session's; it is `.captured`
        /// whenever no earlier session is shown.
        @Published var source = ConsoleLogSource.captured
        /// The session an earlier launch kept that shows under Previous, once one is read.
        @Published private(set) var previousLog: ConsoleSessionLog?
        /// Writes each line to the current session on disk as it is captured; `nil` until
        /// `installConsole()` starts one.
        private(set) var recorder: ConsoleSessionRecorder?

        private var installed = false
        private let driver = ConsoleLogDriver()
        /// Original stdout fd, used to write diagnostics without triggering capture loop.
        private var originalStdoutFd: Int32 = -1
        /// Subject that receives individual log lines, throttled before publishing to `lines`.
        private let lineSubject = PassthroughSubject<LogLine, Never>()
        private var cancellable: AnyCancellable?

        /// An empty store; the plugin shows ``shared``.
        init() {
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

        /// Writes the line to the current session at once, and pushes it into the throttled
        /// pipeline that shows it.
        func ingest(_ line: LogLine) {
            // Recorded before the pipeline's batching, so a crash costs only what the recorder's
            // queue hadn't written yet.
            recorder?.record(line)
            lineSubject.send(line)
        }

        /// Writes each line from now on to the current session of `recorder`, as it is captured.
        func persist(to recorder: ConsoleSessionRecorder) {
            self.recorder = recorder
        }

        /// Shows the lines of `log`, a session an earlier launch kept, read-only, in place of the
        /// captured ones.
        func showPrevious(_ log: ConsoleSessionLog) {
            previousLog = log
            source = .previous
        }

        /// Stops showing the earlier session; the console shows the captured lines again.
        func hidePrevious() {
            previousLog = nil
            if source == .previous {
                source = .captured
            }
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

    // MARK: - Convenience installer

    public extension DebugDrawer {
        /// Install the console capture plugin. Call once at app startup.
        /// Captures stdout, stderr, and os_log entries.
        ///
        /// - Parameter sessions: How many earlier launches' lines are kept on disk, in how many
        ///   bytes, and where; each line is written as it is captured, and the console shows the
        ///   earlier sessions under Previous. ``ConsoleSessionPersistence/off`` writes none.
        func installConsole(sessions: ConsoleSessionPersistence = .standard) {
            // Started before capture begins, so the first line is written too, and once a launch,
            // so a second install doesn't start a second session.
            if ConsoleLogStore.shared.recorder == nil {
                let recorder = ConsoleSessionRecorder(sessions)
                ConsoleLogStore.shared.persist(to: recorder)
                Task { await ConsoleSessionsModel.shared.start(recorder) }
            }
            ConsoleLogStore.shared.install()
            registerGlobal(ConsolePlugin())
        }
    }
#endif
