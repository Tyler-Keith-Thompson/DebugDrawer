import Combine
import DebugDrawer
import Foundation
import os
import OSLogClient
import SwiftUI

#if DEBUG
    // MARK: - Log store

    /// Captures stdout, stderr, and os_log output into a bounded `CaptureBuffer`.
    @MainActor
    public final class ConsoleLogStore: ObservableObject {
        /// The store `installConsole()` fills and the plugin shows, its mutes in the app's
        /// Application Support folder.
        public static let shared = ConsoleLogStore(muteStorage: _ConsoleMuteStorage(directory: _ConsoleMuteStorage.defaultDirectory))

        /// The captured lines, oldest first, within ``capacity`` and ``byteCapacity``.
        @Published public private(set) var lines: [LogLine] = []
        /// How many older lines the bounds dropped since the store was made or last cleared.
        @Published private(set) var droppedLineCount = 0
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

        /// How many lines ``lines`` keeps, 2,000 unless set; the oldest go first.
        public var capacity: Int {
            get { buffer.maxCount }
            set {
                buffer.maxCount = newValue
                publishBuffer()
            }
        }

        /// How many bytes of text ``lines`` keeps, 4 MiB unless set; the oldest lines go first.
        public var byteCapacity: Int {
            get { buffer.maxByteCount }
            set {
                buffer.maxByteCount = newValue
                publishBuffer()
            }
        }

        /// The captured lines, bounded by ``capacity`` and ``byteCapacity``.
        private let buffer = CaptureBuffer<LogLine>(maxCount: 2000, maxByteCount: 4 * 1_048_576) { $0.capturedByteCount }
        /// The buffer's ID after the newest line in ``lines``.
        private var shownEnd = CaptureBuffer<LogLine>.ElementID(rawValue: 0)

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
                    self.buffer.append(contentsOf: batch)
                    self.publishBuffer()
                }
            loadMutes()
        }

        /// Brings ``lines`` and ``droppedLineCount`` up to the buffer with only what changed: the
        /// lines evicted since leave the start and the new ones join the end.
        private func publishBuffer() {
            let change = buffer.snapshot(from: shownEnd)
            let kept = change.keptCount(of: lines.count, before: shownEnd)
            if kept < lines.count || !change.elements.isEmpty {
                lines = lines.suffix(kept) + change.elements
            }
            shownEnd = change.endID
            droppedLineCount = change.evictedCount
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
                // Swift's `print` writes through C's `stdout`, which buffers fully once it finds a
                // pipe behind it, so printed lines would reach the console in chunks. Line
                // buffering keeps each line whole and on time. Set before the redirect: setvbuf
                // flushes what was buffered to where it was headed. stderr stays unbuffered.
                setvbuf(stdout, nil, _IOLBF, 0)
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
            // A read ends wherever the pipe cut the stream, inside a line or a character, so the
            // stream's bytes go through one assembler that keeps what follows the last newline.
            // The handler's calls come one at a time, but it is a Sendable closure; the lock is
            // never contended. `OSAllocatedUnfairLock` rather than `Mutex`, which needs iOS 18;
            // switch once iOS 18 is the minimum.
            let assembler = OSAllocatedUnfairLock(initialState: ConsoleLineAssembler())

            pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                let texts: [String]
                if data.isEmpty {
                    // The end of the stream: its last line shows even without a newline.
                    handle.readabilityHandler = nil
                    texts = assembler.withLock { $0.flush() }.map { [$0] } ?? []
                } else {
                    // Forward to original destination.
                    if originalFd >= 0 {
                        data.withUnsafeBytes { buf in
                            if let ptr = buf.baseAddress {
                                _ = write(originalFd, ptr, data.count)
                            }
                        }
                    }
                    texts = assembler.withLock { $0.lines(in: data) }
                }
                let logLines = texts
                    .filter { !$0.isEmpty }
                    .map { LogLine(timestamp: Date(), text: $0, source: source, level: source == .stderr ? .error : .info) }
                guard !logLines.isEmpty else { return }

                Task { @MainActor [weak self] in
                    guard let self else { return }
                    for line in logLines {
                        self.ingest(line)
                    }
                }
            }
        }

        /// Forgets the captured lines and the dropped count; earlier sessions on disk stay.
        public func clear() {
            buffer.removeAll()
            publishBuffer()
        }
    }
#else
    // The release stand-in: the same members, so the host's code compiles unchanged, and no
    // stdout, stderr or os_log capture behind them.

    /// Release builds capture nothing: this stand-in keeps the debug build's members.
    @MainActor
    public final class ConsoleLogStore: ObservableObject {
        /// The stand-in store.
        public static let shared = ConsoleLogStore()

        /// Always empty.
        /// The captured lines, oldest first, within ``capacity`` and ``byteCapacity``.
        @Published public private(set) var lines: [LogLine] = []
        /// How many older lines the bounds dropped since the store was made or last cleared.
        @Published private(set) var droppedLineCount = 0

        /// Kept, never read: release builds list nothing.
        public var filterLevel: LogLine.Level = .debug

        /// Kept, never read: release builds keep no lines.
        public var capacity = 2000

        /// Kept, never read: release builds keep no lines.
        public var byteCapacity = 4 * 1_048_576

        /// Always empty.
        public var filteredLines: [LogLine] {
            []
        }

        private init() {}

        /// Does nothing: release builds capture nothing.
        public func install() {}

        /// Does nothing.
        public func clear() {}
    }
#endif
