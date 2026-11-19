#if DEBUG
    import Foundation

    /// The request log as a value: what was captured, which requests the log shows, and the filters
    /// and ignore list that pick them. ``NetworkStore`` holds it; ``NetworkSnapshot`` carries it to
    /// the view.
    struct NetworkLogSnapshot: Codable, Equatable, Sendable {
        /// The captured requests, newest first.
        var captured: [NetworkEntry] = []
        /// The WebSocket connections the app opened, the latest first.
        var webSockets: [NetworkWebSocketConnection] = []
        /// Whether the log shows the captured requests, an earlier session's or an imported file's.
        var source = NetworkLogSource.captured
        /// The earlier session shown under Previous, once one is read.
        var previous: NetworkSessionLog?
        /// The requests a HAR file held, while one is imported.
        var imported: NetworkImportedLog?
        /// The last file that couldn't be imported.
        var importIssue: NetworkImportIssue?
        /// The filter text, matched, ignoring case, against each request's method, URL, GraphQL
        /// operation name and response body.
        var filterText = ""
        /// The status filter.
        var filterStatus = NetworkStore.StatusFilter.all
        /// The hosts and domains whose requests the log hides, with their subdomains.
        var ignoredDomains: [NetworkIgnoredDomain] = []
        /// Whether the log lists the requests the ignore list hides, for now.
        var showsIgnored = false
        /// What went wrong reading or saving the ignore list.
        var ignoreIssue: NetworkMocksIssue?

        /// The requests of the source shown: the captured ones, the earlier session's or the
        /// imported file's.
        var shownEntries: [NetworkEntry] {
            switch source {
            case .captured: captured
            case .previous: previous?.entries ?? []
            case .imported: imported?.entries ?? []
            }
        }

        /// The WebSocket connections the log shows: the captured ones, none while an earlier
        /// session or an imported file shows, whose connections are listed as their handshakes.
        var shownWebSockets: [NetworkWebSocketConnection] {
            source == .captured ? webSockets : []
        }

        /// The shown requests that pass the status filter and the filter text, without those to an
        /// ignored host unless `showsIgnored`.
        var filteredEntries: [NetworkEntry] {
            NetworkStore.entries(shownEntries, matching: filterStatus, text: filterText, ignoring: showsIgnored ? [] : ignoredDomains)
        }

        /// The shown WebSocket connections that pass the status filter and the filter text, without
        /// those to an ignored host unless `showsIgnored`.
        var filteredWebSockets: [NetworkWebSocketConnection] {
            NetworkStore.connections(shownWebSockets, matching: filterStatus, text: filterText, ignoring: showsIgnored ? [] : ignoredDomains)
        }

        /// How many of the shown requests and connections that pass the status filter and the
        /// filter text are to an ignored host: the ones the ignore list hides, or, while
        /// `showsIgnored`, the ones it would.
        var ignoredCount: Int {
            guard !ignoredDomains.isEmpty else { return 0 }
            let requests = NetworkStore.entries(shownEntries, matching: filterStatus, text: filterText)
                .count { ignoredDomains.ignores(host: $0.host) }
            let connections = NetworkStore.connections(shownWebSockets, matching: filterStatus, text: filterText)
                .count { ignoredDomains.ignores(host: $0.host) }
            return requests + connections
        }
    }

    extension NetworkStore {
        /// The log as a value: what ``NetworkModel`` hands the plugin's view.
        var logSnapshot: NetworkLogSnapshot {
            NetworkLogSnapshot(
                captured: entries,
                webSockets: webSockets,
                source: source,
                previous: previousLog,
                imported: importedLog,
                importIssue: importIssue,
                filterText: filterText,
                filterStatus: filterStatus,
                ignoredDomains: ignoredDomains,
                showsIgnored: showsIgnored,
                ignoreIssue: ignoreIssue
            )
        }
    }
#endif
