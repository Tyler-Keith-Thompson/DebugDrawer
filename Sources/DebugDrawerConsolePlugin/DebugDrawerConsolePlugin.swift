import Combine
import DebugDrawer
import Foundation
import os
import OSLogClient

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
        @Published private(set) var filter = ConsoleFilter() {
            // The earlier session's page follows the filter, on the main actor, so a change lists
            // its lines at once.
            didSet {
                if let page = previousPage, page.filter != filter {
                    previousPage = page.filtered(by: filter)
                }
            }
        }

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
        /// Which lines ``ingest(_:)`` keeps at all; `installConsole(sessions:includeSystemDebugLogs:)` sets it.
        var ingestFilter = ConsoleIngestFilter()

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
            logSnapshot.filteredLines
        }

        /// The lines the console lists: the captured ones the filter passes, or, while `source` is
        /// `.previous`, the earlier session's page of them.
        var shownLines: [LogLine] {
            logSnapshot.shownLines
        }

        /// How many of the source's lines the mutes hide, of those the other filters pass; while
        /// `showsMuted`, how many they would hide.
        var mutedCount: Int {
            logSnapshot.mutedCount
        }

        /// The mutes the menu offers for the source's lines.
        var muteChoices: [ConsoleMute] {
            logSnapshot.muteChoices
        }

        /// The console as a value: what ``ConsoleModel`` hands the plugin's view.
        var logSnapshot: ConsoleLogSnapshot {
            ConsoleLogSnapshot(
                lines: lines,
                droppedLineCount: droppedLineCount,
                filter: filter,
                searchText: searchText,
                searchIsRegularExpression: searchIsRegularExpression,
                searchIssue: searchIssue,
                muteIssue: muteIssue,
                source: source,
                previousPage: previousPage
            )
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

        /// The page of the session an earlier launch kept that shows under Previous, once one is
        /// read.
        @Published private(set) var previousPage: ConsoleSessionPage?

        /// The session an earlier launch kept that shows under Previous, once one is read.
        var previousLog: ConsoleSessionLog? {
            previousPage?.log
        }
        /// Writes each line to the current session on disk as it is captured; `nil` until
        /// `installConsole()` starts one.
        private(set) var recorder: ConsoleSessionRecorder?

        /// Whether the store captures: not before the first install, while installed, and no
        /// longer once the last install is undone.
        var capture = ConsoleCaptureState.notStarted
        /// Whether the app asked for capture with ``install()`` and hasn't undone it.
        var isInstalledByApp = false
        /// The drawers the Console plugin is installed in.
        var installedDrawers: Set<ObjectIdentifier> = []
        let driver = ConsoleLogDriver()
        /// The OSLogClient calls made last, which the next ones wait for: they are asynchronous,
        /// and an uninstall must not overtake the install before it.
        var osLogWork: Task<Void, Never>?
        /// Original stdout fd, used to write diagnostics without triggering capture loop.
        var originalStdoutFd: Int32 = -1
        /// stdout and stderr, each redirected into a pipe, while the store captures them.
        var streamCaptures: [ConsoleStreamCapture] = []
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
                    // A batch collected before an uninstall can arrive after it.
                    guard let self, !batch.isEmpty, self.capture != .stopped else { return }
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

        /// Writes the line to the current session at once and pushes it into the throttled pipeline that shows it.
        func ingest(_ line: LogLine) {
            // Before the first install lines are kept for when it comes; after the last
            // uninstall, nothing is captured.
            guard capture != .stopped, ingestFilter.keeps(line) else { return }
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
        /// captured ones; its page is worked out off the main actor first.
        func showPrevious(_ log: ConsoleSessionLog) async {
            await showPrevious(ConsoleSessionPage.prepared(log: log, filter: filter))
        }

        /// Shows `page`, of a session an earlier launch kept, read-only, in place of the captured
        /// lines. It is filtered again only when the filter changed while it was worked out.
        func showPrevious(_ page: ConsoleSessionPage) {
            previousPage = page.filter == filter ? page : page.filtered(by: filter)
            source = .previous
        }

        /// Lists up to ``ConsoleSessionPage/lineCount`` more of the earlier session's older lines.
        func showEarlierPreviousLines() {
            previousPage = previousPage?.showingEarlier()
        }

        /// Stops showing the earlier session; the console shows the captured lines again.
        func hidePrevious() {
            previousPage = nil
            if source == .previous {
                source = .captured
            }
        }

        /// Forgets the captured lines and the dropped count; earlier sessions on disk stay.
        public func clear() {
            buffer.removeAll()
            publishBuffer()
        }
    }
#endif
