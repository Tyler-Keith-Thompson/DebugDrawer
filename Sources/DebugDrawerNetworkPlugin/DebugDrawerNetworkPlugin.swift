import Combine
import DebugDrawer
import Foundation
import os

public extension NetworkStore {
    enum StatusFilter: String, CaseIterable, Codable, Sendable {
        case all = "All"
        case success = "2xx"
        case clientError = "4xx"
        case serverError = "5xx"
        case errors = "Errors"
    }
}

#if DEBUG
    /// The requests and WebSocket connections the Network plugin captured, newest first, with the
    /// log's filters, its mock rules, conditioning profiles, ignore list and earlier sessions.
    @MainActor
    public final class NetworkStore: ObservableObject {
        /// The store the plugin `installNetwork()` registers fills and shows, its ignore list in the
        /// app's storage beside the mock rules.
        public static let shared = NetworkStore(
            ignoreStorage: _NetworkIgnoreListStorage(directory: _NetworkMockStorage.defaultDirectory),
            webSocketRecorder: .shared
        )

        /// The captured requests, newest first: at most ``capacity`` of them, whose bodies add up
        /// to at most ``byteCapacity``.
        @Published public private(set) var entries: [NetworkEntry] = []
        /// The log's filter text, matched, ignoring case, against each request's method, URL,
        /// GraphQL operation name and response body.
        @Published public var filterText = ""
        /// The log's status filter.
        @Published public var filterStatus: StatusFilter = .all

        /// How many requests ``entries`` keeps, 200 unless ``setCapacity(_:)`` changed it; the
        /// oldest goes when a new one would pass it.
        public var capacity: Int {
            buffer.maxCount
        }

        /// How many bytes of bodies ``entries`` keeps, 32 MiB unless ``setByteCapacity(_:)``
        /// changed it: each request's body and its response's, as the log kept them. The oldest
        /// requests go when a new one, or a response arriving, would pass it.
        public var byteCapacity: Int {
            buffer.maxByteCount
        }

        /// Keeps at most `capacity` requests from now on; a lower one drops the oldest now.
        ///
        /// - Parameter capacity: The most requests kept.
        /// - Throws: `CaptureBuffer.InvalidLimit.negativeMaxCount` when `capacity` is negative,
        ///   changing nothing.
        public func setCapacity(_ capacity: Int) throws(CaptureBuffer<NetworkEntry>.InvalidLimit) {
            try buffer.setMaxCount(capacity)
            publishBuffer()
        }

        /// Keeps requests whose bodies add up to at most `byteCapacity` bytes from now on; a lower
        /// one drops the oldest now.
        ///
        /// - Parameter byteCapacity: The most bytes of bodies kept.
        /// - Throws: `CaptureBuffer.InvalidLimit.negativeMaxByteCount` when `byteCapacity` is
        ///   negative, changing nothing.
        public func setByteCapacity(_ byteCapacity: Int) throws(CaptureBuffer<NetworkEntry>.InvalidLimit) {
            try buffer.setMaxByteCount(byteCapacity)
            publishBuffer()
        }

        /// The captured requests, oldest first, bounded by ``capacity`` and ``byteCapacity``.
        private let buffer = CaptureBuffer<NetworkEntry>(uncheckedMaxCount: 200, maxByteCount: 32 * 1_048_576) { $0.capturedByteCount }
        /// The buffer's ID after the newest request in ``entries``; the others count down from it.
        private var shownEnd = CaptureBuffer<NetworkEntry>.ElementID(rawValue: 0)

        /// The requests the log shows that pass the status filter and the filter text, without
        /// those to an ignored host unless `showsIgnored`: the captured ones, or the earlier
        /// session's or the imported ones while they show.
        public var filteredEntries: [NetworkEntry] {
            logSnapshot.filteredEntries
        }

        /// The WebSocket connections the log shows that pass the status filter and the filter
        /// text, without those to an ignored host unless `showsIgnored`: the captured ones, none
        /// while an imported file shows.
        var filteredWebSockets: [NetworkWebSocketConnection] {
            logSnapshot.filteredWebSockets
        }

        /// The hosts and domains whose requests and connections the log hides, with their
        /// subdomains, in the order they were added. They are still captured, written to the
        /// session and put in the bug report; only the list leaves them out.
        @Published private(set) var ignoredDomains: [NetworkIgnoredDomain] = []
        /// Whether the log lists the requests the ignore list hides, for now: it is off at each
        /// launch, so the list is quiet again.
        @Published var showsIgnored = false
        /// What went wrong reading or saving the ignore list, if anything.
        @Published private(set) var ignoreIssue: NetworkMocksIssue?
        /// Where the ignore list is kept between launches.
        let ignoreStorage: any NetworkIgnoreListStorage

        /// The WebSocket connections the log shows: the captured ones, none while an earlier
        /// session or an imported file shows, whose connections are listed as their handshakes.
        var shownWebSockets: [NetworkWebSocketConnection] {
            logSnapshot.shownWebSockets
        }

        /// The WebSocket connections the app opened, the latest first, with their frames.
        @Published private(set) var webSockets: [NetworkWebSocketConnection] = []

        /// Which requests the log shows: the captured ones, the earlier session's while `source`
        /// is `.previous`, or the imported file's while it is `.imported`.
        var shownEntries: [NetworkEntry] {
            logSnapshot.shownEntries
        }

        /// The requests a HAR file held, while one is imported.
        @Published private(set) var importedLog: NetworkImportedLog?
        /// The session an earlier launch kept that shows under Previous, once one is read.
        @Published private(set) var previousLog: NetworkSessionLog?
        /// Whether the log shows the captured requests, an earlier session's or the imported
        /// ones; it is `.captured` whenever there is nothing else to show.
        @Published var source = NetworkLogSource.captured
        /// Writes each request as it completes, and each WebSocket connection as it ends, to the
        /// current session on disk; `nil` until `installNetwork()` starts one.
        private(set) var recorder: NetworkSessionRecorder?
        /// The connections written already, so each is written once, when it ends.
        private var recordedWebSockets: Set<NetworkWebSocketConnection.ID> = []
        /// The last file that couldn't be imported, until another is imported or the log cleared.
        @Published private(set) var importIssue: NetworkImportIssue?

        /// Shows `connections` as the WebSocket connections the app opened, and writes each that
        /// has ended to the current session, once.
        func showWebSockets(_ connections: [NetworkWebSocketConnection]) {
            webSockets = connections
            guard let recorder else { return }
            let redaction = recordingRedaction
            for connection in connections where connection.state != .open && !recordedWebSockets.contains(connection.id) {
                recorder.record(connection, redaction: redaction)
            }
            // Only the connections still listed can end later, so the set stays as small as the list.
            recordedWebSockets = Set(connections.filter { $0.state != .open }.map(\.id))
        }

        /// Writes each request from now on to the current session of `recorder`, as it completes.
        func persist(to recorder: NetworkSessionRecorder) {
            self.recorder = recorder
        }

        /// Shows the requests of `log`, a session an earlier launch kept, read-only, in place of
        /// the captured ones.
        func showPrevious(_ log: NetworkSessionLog) {
            previousLog = log
            source = .previous
        }

        /// Stops showing the earlier session; the log shows the captured requests again.
        func hidePrevious() {
            previousLog = nil
            if source == .previous {
                source = .captured
            }
        }

        /// Reads the HAR file at `url` and shows its requests in the log in place of the captured
        /// ones, replacing any imported before; a file that can't be read leaves the log as it is
        /// and becomes `importIssue`.
        func importArchive(from url: URL) {
            do throws(HTTPArchive.ReadError) {
                importedLog = try NetworkImportedLog(contentsOf: url)
                importIssue = nil
                source = .imported
            } catch {
                importIssue = NetworkImportIssue(fileName: url.lastPathComponent, error: error)
            }
        }

        /// Clears the requests the log shows: the captured ones, the earlier session (from the
        /// log; the caller deletes it from disk), or the imported file, after which the log shows
        /// the captured ones again.
        func clearShown() {
            importIssue = nil
            switch source {
            case .captured:
                clear()
            case .previous:
                hidePrevious()
            case .imported:
                importedLog = nil
                source = .captured
            }
        }

        private var installed = false

        /// Records the WebSocket connections this store shows; `clear()` empties it.
        let webSocketRecorder: NetworkWebSocketRecorder

        /// - Parameters:
        ///   - ignoreStorage: Where the ignore list is kept between launches; nothing is read
        ///     until `loadIgnoreList(adding:)`.
        ///   - webSocketRecorder: Records the WebSocket connections the store shows; its own unless given.
        init(ignoreStorage: any NetworkIgnoreListStorage, webSocketRecorder: NetworkWebSocketRecorder? = nil) {
            self.ignoreStorage = ignoreStorage
            self.webSocketRecorder = webSocketRecorder ?? NetworkWebSocketRecorder(connectionCapacity: 50, frameCapacity: 500)
            self.webSocketRecorder.showChanges(in: self)
        }

        /// Starts capturing: registers the plugin's URL protocol for `URLSession.shared`, adds it
        /// to every `URLSessionConfiguration` read from then on, and records WebSocket tasks. A
        /// drawer that adds the Network plugin calls it; a second call does nothing. What is
        /// captured goes to the store of the drawer that installed the plugin last.
        public func install() {
            guard !installed else { return }
            installed = true
            NetworkInterception.start()
        }

        /// Stops capturing what ``install()`` started and forgets the captured requests and
        /// connections: the URL protocol is unregistered, every method the plugin replaced gets
        /// its original implementation back, and a session made while capturing sends its
        /// requests past the plugin. The mock rules, conditioning profiles, ignore list and
        /// earlier sessions stay saved for the next install. A drawer that removes the Network
        /// plugin, and holds it in no other drawer, calls it; a second call does nothing.
        public func uninstall() {
            uninstall(stoppingCapture: true)
        }

        /// Forgets what was captured, and stops capturing when `stoppingCapture`.
        func uninstall(stoppingCapture: Bool) {
            guard installed else { return }
            installed = false
            if stoppingCapture {
                NetworkInterception.stop()
            }
            clear()
        }

        func recordStart(_ entry: NetworkEntry) {
            buffer.append(entry)
            publishBuffer()
            // A mock's answer is recorded complete in one step.
            if entry.isComplete {
                persist(entry)
            }
        }

        func recordCompletion(id: UUID, _ completion: NetworkCompletion) {
            var completed: NetworkEntry?
            update(id) { entry in
                entry.statusCode = completion.statusCode
                entry.responseHeaders = completion.headers
                entry.response = completion.body
                entry.duration = completion.duration
                entry.error = completion.error
                entry.isComplete = true
                completed = entry
            }
            if let completed {
                persist(completed)
            }
        }

        /// Changes the kept request with `id` in place, in the buffer and in ``entries``; does
        /// nothing when the log no longer keeps it.
        private func update(_ id: UUID, _ body: (inout NetworkEntry) -> Void) {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
            var changed: NetworkEntry?
            let bufferID = CaptureBuffer<NetworkEntry>.ElementID(rawValue: shownEnd.rawValue - 1 - UInt64(index))
            buffer.update(bufferID) { entry in
                body(&entry)
                changed = entry
            }
            guard let changed else { return }
            entries[index] = changed
            // The change can pass the byte bound, which evicts the oldest.
            publishBuffer()
        }

        /// Shows what changed in the buffer in ``entries``, newest first.
        ///
        /// Takes only what changed since the last time: `entries` holds the buffer's IDs below
        /// `shownEnd`, so the requests the buffer evicted since leave its end and the new ones
        /// join its start, without copying the buffer whole on every request.
        private func publishBuffer() {
            let change = buffer.snapshot(from: shownEnd)
            let kept = change.keptCount(of: entries.count, before: shownEnd)
            if kept < entries.count || !change.elements.isEmpty {
                entries = change.elements.reversed() + entries.prefix(kept)
            }
            shownEnd = change.endID
        }

        /// The drawer whose redaction rules mask what this store writes to the session; weak, as
        /// the drawer holds the plugin that holds this store (`NetworkStore+Recording.swift`).
        weak var recordingDrawer: DebugDrawer?

        func recordMetrics(id: UUID, metrics: NetworkTimingMetrics) {
            update(id) { $0.metrics = metrics }
        }

        /// Clears the captured requests and WebSocket connections.
        public func clear() {
            buffer.removeAll()
            publishBuffer()
            webSockets.removeAll()
            webSocketRecorder.clear()
        }

        // MARK: Ignore list

        private static let logger = Logger(subsystem: "DebugDrawerNetworkPlugin", category: "NetworkStore")

        /// How many of the requests and connections the log shows that pass the status filter and
        /// the filter text are to an ignored host: the ones the ignore list hides, or, while
        /// `showsIgnored`, the ones it would.
        var ignoredCount: Int {
            logSnapshot.ignoredCount
        }

        /// Reads the saved ignore list, then adds each of `domains` it doesn't hold, at the end.
        /// The added ones aren't saved until the list is next changed, so a launch writes nothing.
        func loadIgnoreList(adding domains: [NetworkIgnoredDomain] = []) {
            var loaded: [NetworkIgnoredDomain] = []
            do {
                if let data = try ignoreStorage.readIgnoreList() {
                    loaded = try NetworkIgnoreListFile.decode(data)
                }
                ignoreIssue = nil
            } catch let error as NetworkMockRuleFile.ReadError {
                Self.logger.error("Saved ignore list not loaded: \(String(describing: error), privacy: .public)")
                ignoreIssue = switch error {
                case .unreadable: .unreadable
                case let .unsupportedVersion(version): .unsupportedVersion(version)
                }
            } catch {
                Self.logger.error("Saved ignore list not read: \(error.localizedDescription, privacy: .public)")
                ignoreIssue = .unreadable
            }
            for domain in domains where !loaded.contains(domain) {
                loaded.append(domain)
            }
            ignoredDomains = loaded
        }

        /// Hides the requests to `domain` and its subdomains from the log, and saves the list.
        func ignore(_ domain: NetworkIgnoredDomain) {
            guard !ignoredDomains.contains(domain) else { return }
            ignoredDomains.append(domain)
            saveIgnoreList()
        }

        /// Lists the requests to `domain` again, and saves the list.
        func stopIgnoring(_ domain: NetworkIgnoredDomain) {
            guard let index = ignoredDomains.firstIndex(of: domain) else { return }
            ignoredDomains.remove(at: index)
            saveIgnoreList()
        }

        private func saveIgnoreList() {
            do {
                try ignoreStorage.writeIgnoreList(NetworkIgnoreListFile.encode(ignoredDomains))
                if ignoreIssue == .notSaved { ignoreIssue = nil }
            } catch {
                Self.logger.error("Ignore list not saved: \(error.localizedDescription, privacy: .public)")
                ignoreIssue = .notSaved
            }
        }
    }
#endif
