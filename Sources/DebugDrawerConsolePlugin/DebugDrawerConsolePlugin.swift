#if DEBUG
    import Combine
    import DebugDrawer
    import Foundation
    import os
    import OSLogClient
    import SwiftUI

    // MARK: - Log line model

    public struct LogLine: Identifiable, Sendable {
        public let id = UUID()
        public let timestamp: Date
        public let text: String
        public let source: Source
        public let level: Level
        /// The os_log subsystem it was logged to (`com.example.shop`), or the one an app's logger
        /// gave ``ConsoleLogSink``; empty for stdout and stderr.
        public let subsystem: String
        /// The os_log category it was logged to (`networking`), or the one an app's logger gave
        /// ``ConsoleLogSink``; empty for stdout and stderr.
        public let category: String
        /// The key/value fields an app's logger attached through ``ConsoleLogSink``; empty for
        /// os_log, stdout and stderr lines.
        public let metadata: [String: String]

        /// A line as it was captured.
        ///
        /// - Parameters:
        ///   - timestamp: When it was logged.
        ///   - text: What was logged, without its subsystem or category.
        ///   - source: Where it was captured from.
        ///   - level: Its level.
        ///   - subsystem: The os_log subsystem; empty for stdout and stderr.
        ///   - category: The os_log category; empty for stdout and stderr.
        ///   - metadata: The fields the app's logger attached; empty for os_log, stdout and stderr.
        init(
            timestamp: Date, text: String, source: Source, level: Level, subsystem: String = "", category: String = "",
            metadata: [String: String] = [:]
        ) {
            self.timestamp = timestamp
            self.text = text
            self.source = source
            self.level = level
            self.subsystem = subsystem
            self.category = category
            self.metadata = metadata
        }

        /// Where a line was captured from.
        public enum Source: String, Sendable {
            case stdout, stderr, oslog
            /// The app's own logger, through ``ConsoleLogSink``.
            case sink
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

    // MARK: - Log store

    /// Captures stdout, stderr, and os_log output into a ring buffer.
    @MainActor
    public final class ConsoleLogStore: ObservableObject {
        /// The store `installConsole()` fills and the plugin shows, its mutes in the app's
        /// Application Support folder.
        public static let shared = ConsoleLogStore(muteStorage: _ConsoleMuteStorage(directory: _ConsoleMuteStorage.defaultDirectory))

        @Published public private(set) var lines: [LogLine] = []
        /// Which lines the console lists. The level, time range and whether muted lines show are
        /// set through their own properties, the search through `searchText`, and the mutes
        /// through `mute(_:)`, which saves them.
        @Published private(set) var filter = ConsoleFilter()

        /// The lowest level the console shows.
        public var filterLevel: LogLine.Level {
            get { filter.level }
            set { filter.level = newValue }
        }

        /// When a line must be logged to show.
        var timeRange: ConsoleTimeRange {
            get { filter.timeRange }
            set { filter.timeRange = newValue }
        }

        /// Whether the muted lines show anyway, for now; off at each launch.
        var showsMuted: Bool {
            get { filter.showsMuted }
            set { filter.showsMuted = newValue }
        }

        /// The search field's text, matched as text or, with `searchIsRegularExpression`, as a
        /// pattern; each change compiles it once.
        @Published var searchText = "" {
            didSet { updateSearch() }
        }

        /// Whether `searchText` is a regular expression.
        @Published var searchIsRegularExpression = false {
            didSet { updateSearch() }
        }

        /// Why `searchText` isn't a pattern, while it isn't one; the filter keeps the last search
        /// that was.
        @Published private(set) var searchIssue: ConsoleSearch.InvalidPattern?
        /// What went wrong reading or saving the mutes, if anything.
        @Published var muteIssue: ConsoleMuteIssue?
        /// Where the mutes are kept between launches.
        let muteStorage: any ConsoleMuteStorage

        /// Maximum number of lines retained in the ring buffer.
        public var capacity = 2000

        /// The captured lines the console lists: those the level, search, mutes and time range
        /// pass.
        public var filteredLines: [LogLine] {
            filter.apply(to: lines)
        }

        /// The lines the console lists: the captured ones, or the earlier session's while `source`
        /// is `.previous`, that the filter passes.
        var shownLines: [LogLine] {
            filter.apply(to: sourceLines)
        }

        /// How many of the source's lines the mutes hide, of those the other filters pass; while
        /// `showsMuted`, how many they would hide.
        var mutedCount: Int {
            filter.mutedCount(in: sourceLines)
        }

        /// Every line of the source, before the filter: the captured ones, or the earlier
        /// session's while `source` is `.previous`.
        var sourceLines: [LogLine] {
            switch source {
            case .captured: lines
            case .previous: previousLog?.lines ?? []
            }
        }

        /// Whether the console shows the captured lines or an earlier session's; it is `.captured`
        /// whenever no earlier session is shown.
        @Published var source = ConsoleLogSource.captured {
            // A line's time belongs to its session, so "Since This Line" doesn't carry over to
            // the other source, where it would hide every line or none.
            didSet {
                if source != oldValue, case .since = timeRange { timeRange = .all }
            }
        }

        /// The session an earlier launch kept that shows under Previous, once one is read.
        @Published private(set) var previousLog: ConsoleSessionLog?
        /// Writes each line to the current session on disk as it is captured; `nil` until
        /// `installConsole()` starts one.
        private(set) var recorder: ConsoleSessionRecorder?

        private var installed = false
        private let driver = ConsoleLogDriver()
        /// Original stdout fd, used to write diagnostics without triggering capture loop.
        private var originalStdoutFd: Int32 = -1
        /// The pipes stdout and stderr are redirected into, held for as long as the store lives: a
        /// pipe released closes its reading end, and the app's next write to either stream would
        /// then raise SIGPIPE.
        private var capturePipes: [Pipe] = []
        /// Subject that receives individual log lines, throttled before publishing to `lines`.
        private let lineSubject = PassthroughSubject<LogLine, Never>()
        private var cancellable: AnyCancellable?

        /// An empty store with the mutes `muteStorage` saved; the plugin shows ``shared``.
        ///
        /// - Parameter muteStorage: Where the mutes are kept between launches; they are read now.
        init(muteStorage: any ConsoleMuteStorage) {
            self.muteStorage = muteStorage
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
            loadMutes()
        }

        /// Compiles the search field's text into the filter, or, when it isn't a pattern, names
        /// why and keeps the last search that was.
        private func updateSearch() {
            do {
                filter.search = try ConsoleSearch(searchText, isRegularExpression: searchIsRegularExpression)
                searchIssue = nil
            } catch {
                searchIssue = error
            }
        }

        // MARK: - Mutes

        private static let logger = Logger(subsystem: "DebugDrawerConsolePlugin", category: "ConsoleLogStore")

        /// Hides the lines `mute` matches, from now on and in later launches.
        func mute(_ mute: ConsoleMute) {
            guard !filter.mutes.contains(mute) else { return }
            filter.mutes.append(mute)
            saveMutes()
        }

        /// Shows the lines `mute` hid again.
        func unmute(_ mute: ConsoleMute) {
            guard let index = filter.mutes.firstIndex(of: mute) else { return }
            filter.mutes.remove(at: index)
            saveMutes()
        }

        /// Shows every muted line again, and forgets the mutes.
        func unmuteAll() {
            guard !filter.mutes.isEmpty else { return }
            filter.mutes.removeAll()
            filter.showsMuted = false
            saveMutes()
        }

        /// Reads the saved mutes into the filter; a file this build can't read mutes nothing and
        /// says why in `muteIssue`.
        private func loadMutes() {
            do {
                if let data = try muteStorage.readMutes() {
                    filter.mutes = try ConsoleMuteListFile.decode(data)
                }
                muteIssue = nil
            } catch let error as ConsoleMuteListFile.ReadError {
                Self.logger.error("Saved console mutes not loaded: \(String(describing: error), privacy: .public)")
                muteIssue = switch error {
                case .unreadable: .unreadable
                case let .unsupportedVersion(version): .unsupportedVersion(version)
                }
            } catch {
                Self.logger.error("Saved console mutes not read: \(error.localizedDescription, privacy: .public)")
                muteIssue = .unreadable
            }
        }

        /// Writes the mutes to their storage; a failure says so in `muteIssue`, and the mutes
        /// apply until the app quits.
        private func saveMutes() {
            do {
                try muteStorage.writeMutes(ConsoleMuteListFile.encode(filter.mutes))
                if muteIssue == .notSaved { muteIssue = nil }
            } catch {
                // Logged once per change a person makes, so it can't loop through the console's
                // own capture.
                Self.logger.error("Console mutes not saved: \(error.localizedDescription, privacy: .public)")
                muteIssue = .notSaved
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
            capturePipes.append(pipe)
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
#endif
