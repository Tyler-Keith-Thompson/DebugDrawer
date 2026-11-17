#if DEBUG
    import Combine
    import DebugDrawer
    import Foundation
    import os
    import SwiftUI

    @MainActor
    public final class NetworkStore: ObservableObject {
        /// The store `installNetwork()` fills and the plugin shows, its ignore list in the app's
        /// storage beside the mock rules.
        public static let shared = NetworkStore(ignoreStorage: _NetworkIgnoreListStorage(directory: _NetworkMockStorage.defaultDirectory))

        @Published public private(set) var entries: [NetworkEntry] = []
        @Published public var filterText = ""
        @Published public var filterStatus: StatusFilter = .all

        public var capacity = 200

        public enum StatusFilter: String, CaseIterable {
            case all = "All"
            case success = "2xx"
            case clientError = "4xx"
            case serverError = "5xx"
            case errors = "Errors"
        }

        /// The requests the log shows that pass the status filter and the filter text, without
        /// those to an ignored host unless `showsIgnored`: the captured ones, or the earlier
        /// session's or the imported ones while they show.
        public var filteredEntries: [NetworkEntry] {
            Self.entries(shownEntries, matching: filterStatus, text: filterText, ignoring: showsIgnored ? [] : ignoredDomains)
        }

        /// The WebSocket connections the log shows that pass the status filter and the filter
        /// text, without those to an ignored host unless `showsIgnored`: the captured ones, none
        /// while an imported file shows.
        var filteredWebSockets: [NetworkWebSocketConnection] {
            Self.connections(shownWebSockets, matching: filterStatus, text: filterText, ignoring: showsIgnored ? [] : ignoredDomains)
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
            source == .captured ? webSockets : []
        }

        /// The WebSocket connections the app opened, the latest first, with their frames.
        @Published private(set) var webSockets: [NetworkWebSocketConnection] = []

        /// Which requests the log shows: the captured ones, the earlier session's while `source`
        /// is `.previous`, or the imported file's while it is `.imported`.
        var shownEntries: [NetworkEntry] {
            switch source {
            case .captured: entries
            case .previous: previousLog?.entries ?? []
            case .imported: importedLog?.entries ?? []
            }
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

        /// The requests in `entries` to a host none of `ignored` matches that pass the status
        /// filter `status` and contain `text` (ignoring case) in the URL, the method, the GraphQL
        /// operation name or the response body. Empty text matches every request.
        nonisolated static func entries(
            _ entries: [NetworkEntry],
            matching status: StatusFilter,
            text: String,
            ignoring ignored: [NetworkIgnoredDomain] = []
        ) -> [NetworkEntry] {
            var result = ignored.isEmpty ? entries : entries.filter { !ignored.ignores(host: $0.host) }
            switch status {
            case .all: break
            case .success: result = result.filter { ($0.statusCode ?? 0) >= 200 && ($0.statusCode ?? 0) < 300 }
            case .clientError: result = result.filter { ($0.statusCode ?? 0) >= 400 && ($0.statusCode ?? 0) < 500 }
            case .serverError: result = result.filter { ($0.statusCode ?? 0) >= 500 }
            case .errors: result = result.filter(\.isFailure)
            }
            if !text.isEmpty {
                let query = text.lowercased()
                result = result.filter {
                    $0.url.lowercased().contains(query) ||
                        $0.method.lowercased().contains(query) ||
                        ($0.graphQLOperationName?.lowercased().contains(query) ?? false) ||
                        ($0.prettyResponseBody?.lowercased().contains(query) ?? false)
                }
            }
            return result
        }

        /// The connections in `connections` to a host none of `ignored` matches that pass the
        /// status filter `status` and contain `text` (ignoring case) in the URL, the method ("WS")
        /// or a text frame. A connection has no HTTP status, so All shows every one, Errors those
        /// that failed, and the others none.
        nonisolated static func connections(
            _ connections: [NetworkWebSocketConnection],
            matching status: StatusFilter,
            text: String,
            ignoring ignored: [NetworkIgnoredDomain] = []
        ) -> [NetworkWebSocketConnection] {
            var result = ignored.isEmpty ? connections : connections.filter { !ignored.ignores(host: $0.host) }
            switch status {
            case .all: break
            case .success, .clientError, .serverError: result = []
            case .errors: result = result.filter(\.isFailure)
            }
            if !text.isEmpty {
                let query = text.lowercased()
                result = result.filter { connection in
                    connection.url.lowercased().contains(query) || "ws".contains(query)
                        || connection.frames.contains { $0.text?.lowercased().contains(query) ?? false }
                }
            }
            return result
        }

        /// Shows `connections` as the WebSocket connections the app opened, and writes each that
        /// has ended to the current session, once.
        func showWebSockets(_ connections: [NetworkWebSocketConnection]) {
            webSockets = connections
            guard let recorder else { return }
            let redaction = DebugDrawer.shared.redaction
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

        /// - Parameter ignoreStorage: Where the ignore list is kept between launches; nothing is
        ///   read until `loadIgnoreList(adding:)`.
        init(ignoreStorage: any NetworkIgnoreListStorage) {
            self.ignoreStorage = ignoreStorage
        }

        public func install() {
            guard !installed else { return }
            installed = true
            // Register for URLSession.shared
            URLProtocol.registerClass(DebugNetworkProtocol.self)
            // Swizzle URLSessionConfiguration so custom sessions also get intercepted
            URLSessionConfiguration.swizzleProtocolClasses()
            // WebSocket tasks bypass URL protocols, so their traffic is recorded on the tasks.
            NetworkWebSocketInterception.install()
        }

        func recordStart(_ entry: NetworkEntry) {
            entries.insert(entry, at: 0)
            if entries.count > capacity {
                entries.removeLast(entries.count - capacity)
            }
            // A mock's answer is recorded complete in one step.
            if entry.isComplete {
                persist(entry)
            }
        }

        func recordCompletion(id: UUID, _ completion: NetworkCompletion) {
            guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
            entries[idx].statusCode = completion.statusCode
            entries[idx].responseHeaders = completion.headers
            entries[idx].responseBody = completion.body
            entries[idx].duration = completion.duration
            entries[idx].error = completion.error
            entries[idx].isComplete = true
            persist(entries[idx])
        }

        /// Writes `entry`, complete, to the current session, masked by the drawer's rules as they
        /// are now, with the request it resends when the log still holds it.
        private func persist(_ entry: NetworkEntry) {
            guard let recorder else { return }
            let original = entry.replayOf.flatMap { id in entries.first { $0.id == id } }
            recorder.record(entry, original: original, redaction: DebugDrawer.shared.redaction)
        }

        func recordMetrics(id: UUID, metrics: NetworkTimingMetrics) {
            guard let idx = entries.firstIndex(where: { $0.id == id }) else { return }
            entries[idx].metrics = metrics
        }

        /// Clears the captured requests and WebSocket connections.
        public func clear() {
            entries.removeAll()
            webSockets.removeAll()
            NetworkWebSocketRecorder.shared.clear()
        }

        // MARK: Ignore list

        private static let logger = Logger(subsystem: "DebugDrawerNetworkPlugin", category: "NetworkStore")

        /// How many of the requests and connections the log shows that pass the status filter and
        /// the filter text are to an ignored host: the ones the ignore list hides, or, while
        /// `showsIgnored`, the ones it would.
        var ignoredCount: Int {
            guard !ignoredDomains.isEmpty else { return 0 }
            let requests = Self.entries(shownEntries, matching: filterStatus, text: filterText)
                .count { ignoredDomains.ignores(host: $0.host) }
            let connections = Self.connections(shownWebSockets, matching: filterStatus, text: filterText)
                .count { ignoredDomains.ignores(host: $0.host) }
            return requests + connections
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
