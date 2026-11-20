import DebugDrawerReceiver
import Foundation

// What the app state reset serves a sidecar and takes from it: the listing, the reset's progress
// and report, and the commands. Names, counts and sizes only, never a value.

extension AppStateResetRequests {
    /// One thing a category would clear, as a sidecar lists it: a key, a path, a cookie domain, a
    /// keychain item's service. Never a value.
    public struct Item: Codable, Equatable, Sendable {
        /// What it is ("Documents/notes.txt", "onboarded", "example.com").
        public let text: String
        /// Its size, count, domain or class, or `nil`.
        public let detail: String?

        /// An item.
        ///
        /// - Parameters:
        ///   - text: What it is.
        ///   - detail: Its size, count, domain or class.
        public init(text: String, detail: String?) {
            self.text = text
            self.detail = detail
        }
    }

    /// What one category would clear, as read.
    public struct CategoryListing: Codable, Equatable, Sendable, Identifiable {
        /// The category.
        public let category: AppStateReset.Category
        /// What it would clear, in a few words ("12 keys", "4 items · 4.2 MB").
        public let summary: String
        /// What it would clear, item by item, the first ``AppStateResetRequests/maximumListedItems``.
        public let items: [Item]
        /// How many more items it would clear than `items` lists.
        public let unlistedCount: Int
        /// Why it can't be read, such as the keychain's error; `nil` when it can.
        public let problem: String?
        /// A digest of what it would clear, by name, not size: a reset confirms it, and is
        /// refused once it changes.
        public let revision: String

        /// The category.
        public var id: AppStateReset.Category {
            category
        }

        /// A category's listing.
        ///
        /// - Parameters:
        ///   - category: The category.
        ///   - summary: What it would clear, in a few words.
        ///   - items: What it would clear, item by item.
        ///   - unlistedCount: How many more it would clear.
        ///   - problem: Why it can't be read.
        ///   - revision: A digest of what it would clear.
        public init(category: AppStateReset.Category, summary: String, items: [Item], unlistedCount: Int, problem: String?, revision: String) {
            self.category = category
            self.summary = summary
            self.items = items
            self.unlistedCount = unlistedCount
            self.problem = problem
            self.revision = revision
        }
    }

    /// What every allowed category would clear, as read at one time.
    public struct Listing: Codable, Equatable, Sendable {
        /// When it was read.
        public let read: Date
        /// Each allowed category's, in ``AppStateReset/Category``'s order.
        public let categories: [CategoryListing]

        /// A listing.
        ///
        /// - Parameters:
        ///   - read: When it was read.
        ///   - categories: Each allowed category's.
        public init(read: Date, categories: [CategoryListing]) {
            self.read = read
            self.categories = categories
        }
    }

    /// A category a sidecar confirms clearing, at the revision it showed.
    public struct Confirmation: Codable, Equatable, Sendable {
        /// The category.
        public let category: AppStateReset.Category
        /// The ``CategoryListing/revision`` the sidecar showed.
        public let revision: String

        /// A confirmation.
        ///
        /// - Parameters:
        ///   - category: The category.
        ///   - revision: The revision the sidecar showed.
        public init(category: AppStateReset.Category, revision: String) {
            self.category = category
            self.revision = revision
        }
    }

    /// A reset accepted and waiting for the app to come to the foreground.
    public struct PendingReset: Codable, Equatable, Sendable {
        /// The categories it clears.
        public let categories: [AppStateReset.Category]
        /// When the sidecar asked for it.
        public let requested: Date

        /// A waiting reset.
        ///
        /// - Parameters:
        ///   - categories: The categories it clears.
        ///   - requested: When the sidecar asked for it.
        public init(categories: [AppStateReset.Category], requested: Date) {
            self.categories = categories
            self.requested = requested
        }
    }

    /// What the capability is doing.
    public enum Activity: Codable, Equatable, Sendable {
        /// Nothing.
        case idle
        /// Reading what each allowed category holds.
        case reading
        /// A reset is accepted, and runs as the app next comes to the foreground.
        case waitingForForeground(PendingReset)
        /// Deleting.
        case resetting
    }

    /// What a reset did to one category.
    public struct CategoryResult: Codable, Equatable, Sendable {
        /// The category.
        public let category: AppStateReset.Category
        /// How many items it deleted (keys, keychain items, entries, cookies; one for the URL
        /// cache and the app's cleanup).
        public let cleared: Int
        /// What it couldn't delete, and why, the first ``AppStateResetRequests/maximumListedItems``.
        public let failures: [String]

        /// A category's result.
        ///
        /// - Parameters:
        ///   - category: The category.
        ///   - cleared: How many items it deleted.
        ///   - failures: What it couldn't delete, and why.
        public init(category: AppStateReset.Category, cleared: Int, failures: [String]) {
            self.category = category
            self.cleared = cleared
            self.failures = failures
        }
    }

    /// What became of a reset.
    public enum Outcome: Codable, Equatable, Sendable {
        /// It ran: each category's result, in the order it ran.
        case applied([CategoryResult])
        /// It didn't run, and nothing was deleted: what these categories would clear changed
        /// between the sidecar's confirmation and the reset. The listing shows what they hold now.
        case notApplied(changed: [AppStateReset.Category])
    }

    /// The last reset in this session.
    public struct Report: Codable, Equatable, Sendable {
        /// When it finished.
        public let finished: Date
        /// What became of it.
        public let outcome: Outcome

        /// A report.
        ///
        /// - Parameters:
        ///   - finished: When it finished.
        ///   - outcome: What became of it.
        public init(finished: Date, outcome: Outcome) {
            self.finished = finished
            self.outcome = outcome
        }
    }

    /// What a sidecar sees. Outside a session it holds only the allowed categories.
    public struct Snapshot: Codable, Equatable, Sendable {
        /// The open session's ID, or `nil` while none is open.
        public var sessionID: UUID?
        /// The categories the host allows a sidecar to clear, in ``AppStateReset/Category``'s
        /// order.
        public var allowed: [AppStateReset.Category]
        /// What the capability is doing.
        public var activity: Activity
        /// What each allowed category would clear, once a sidecar has asked in this session.
        public var listing: Listing?
        /// The last reset in this session, or `nil`.
        public var lastReset: Report?
        /// The URL a sidecar opens to bring the app to the foreground, where the reset runs (its
        /// URL scheme), or `nil` when the host declares none; a Mac sidecar opens the app by its
        /// bundle identifier.
        public var launchURL: URL?

        /// A snapshot.
        ///
        /// - Parameters:
        ///   - sessionID: The open session's ID.
        ///   - allowed: The categories the host allows.
        ///   - activity: What the capability is doing.
        ///   - listing: What each allowed category would clear.
        ///   - lastReset: The last reset in this session.
        ///   - launchURL: The URL a sidecar opens to bring the app to the foreground.
        public init(
            sessionID: UUID?, allowed: [AppStateReset.Category], activity: Activity, listing: Listing?, lastReset: Report?, launchURL: URL?
        ) {
            self.sessionID = sessionID
            self.allowed = allowed
            self.activity = activity
            self.listing = listing
            self.lastReset = lastReset
            self.launchURL = launchURL
        }
    }

    /// What a sidecar asks.
    public enum Command: Codable, Equatable, Sendable {
        /// Reads what each allowed category would clear into ``Snapshot/listing``.
        case refresh
        /// Clears the confirmed categories as the app next comes to the foreground, in place of a
        /// reset still waiting; refused unless each is allowed and confirmed at its listing's
        /// current revision.
        case reset([Confirmation])
        /// Drops a reset still waiting for the foreground.
        case cancel
    }
}
