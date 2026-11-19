import Foundation

// Public because it is `NetworkModel`'s `Command`, and opaque: the actions it wraps stay internal,
// as their payloads (an ignored domain, a log source) are the plugin's own types. An enum's cases
// share its access level, so the public type is a struct around the internal enum.

#if DEBUG
    /// Something the Network plugin's view asks ``NetworkModel`` to do: change a filter, clear the
    /// log, save a mock rule, resend a request. `Codable`, so a transport can carry it from another
    /// process.
    public struct NetworkCommand: Codable, Sendable {
        /// What to do, by the part of the plugin it changes.
        enum Action: Codable, Sendable {
            case log(Log)
            case sessions(Sessions)
            case mocks(Mocks)
            case conditions(Conditions)
            case replays(Replays)
        }

        /// A change to the request log, its filters or its ignore list.
        enum Log: Codable, Sendable {
            case setFilterText(String)
            case setFilterStatus(NetworkStore.StatusFilter)
            case setSource(NetworkLogSource)
            case setShowsIgnored(Bool)
            /// Clears what the log shows: the captured requests, the imported file, or, under
            /// Previous, the earlier session shown, which is deleted from disk.
            case clearShown
            case importArchive(URL)
            case ignore(NetworkIgnoredDomain)
            case stopIgnoring(NetworkIgnoredDomain)
        }

        /// A change to the sessions earlier launches kept.
        enum Sessions: Codable, Sendable {
            case reload
            case show(NetworkSessionSummary.ID)
            case delete([NetworkSessionSummary.ID])
        }

        /// A change to the mock rules.
        enum Mocks: Codable, Sendable {
            case save(NetworkMockRule)
            case setEnabled(NetworkMockRule.ID, Bool)
            case move(NetworkMockRule.ID, offset: Int)
            case delete(NetworkMockRule.ID)
            /// Keeps a body file a rule names, ahead of the rule's save.
            case addBody(NetworkMockBodyUpload)
            /// A body file the user chose couldn't be read where the view runs.
            case bodyUnreadable
        }

        /// A change to the conditioning profiles.
        enum Conditions: Codable, Sendable {
            case save(NetworkConditionProfile)
            case setEnabled(NetworkConditionProfile.ID, Bool)
            case move(NetworkConditionProfile.ID, offset: Int)
            case delete(NetworkConditionProfile.ID)
        }

        /// A request to send again.
        enum Replays: Codable, Sendable {
            /// Sends the captured request with this id again, unchanged.
            case resend(NetworkEntry.ID)
            /// Sends an edited request, as a replay of the captured request `original`.
            case resendEdited(NetworkReplayRequest, original: NetworkEntry.ID)
        }

        let action: Action

        init(_ action: Action) {
            self.action = action
        }
    }
#else
    /// Release builds capture nothing: this stand-in asks for nothing.
    public struct NetworkCommand: Codable, Sendable {}
#endif
