import DebugDrawerNetwork
import Foundation

// Public because it is `NetworkModel`'s `Snapshot`, and opaque: its fields stay internal, so the
// plugin's types (an ignored domain, a session's summary) don't become API. A reader outside the
// module carries it whole, encoded.

#if DEBUG
    /// Everything the Network plugin shows, as a value: the request log with its filters, the
    /// mock rules, the conditioning profiles, where each resend stands, and the earlier sessions.
    ///
    /// ``NetworkModel`` makes it; the plugin's view draws it. It is `Codable`, so a transport can
    /// carry it to another process.
    public struct NetworkSnapshot: Codable, Equatable, Sendable {
        /// The request log, its filters and its ignore list.
        var log = NetworkLogSnapshot()
        /// Every mock rule, in the order they are tried.
        var mockRules: [NetworkMockRule] = []
        /// What went wrong reading or saving the mock rules.
        var mocksIssue: NetworkMocksIssue?
        /// Every conditioning profile, in the order they are listed.
        var conditionProfiles: [NetworkConditionProfile] = []
        /// What went wrong reading or saving the profiles.
        var conditionsIssue: NetworkMocksIssue?
        /// Where the last resend of each captured request stands, by the captured request's id.
        var replayStatuses: [NetworkEntry.ID: NetworkReplayStatus] = [:]
        /// The sessions earlier launches kept, the newest first.
        var sessions: [NetworkSessionSummary] = []
        /// The session last asked for that couldn't be read.
        var unreadableSession: NetworkSessionSummary?
    }

    extension NetworkSnapshot {
        /// How many mock rules are on.
        var enabledMockCount: Int {
            mockRules.count(where: \.isEnabled)
        }

        /// The sources the log can show: the captured requests, an earlier launch's while one is
        /// kept, and an imported file's while one is.
        var availableSources: [NetworkLogSource] {
            NetworkLogSource.allCases.filter { source in
                switch source {
                case .captured: true
                case .previous: !sessions.isEmpty
                case .imported: log.imported != nil
                }
            }
        }
    }
#else
    /// Release builds capture nothing: this stand-in holds nothing.
    public struct NetworkSnapshot: Codable, Equatable, Sendable {}
#endif
