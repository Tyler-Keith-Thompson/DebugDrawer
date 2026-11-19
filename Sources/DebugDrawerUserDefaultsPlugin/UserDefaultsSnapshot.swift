import Foundation

// Public because it is `UserDefaultsModel`'s `Snapshot`, and opaque: its fields stay internal, so
// a reader outside the module carries it whole, encoded. It holds the suites offered, the one
// shown, its keys as read and the filters; which keys the filters let through is worked out from
// them, and the view formats all of it.

#if DEBUG
    /// Everything the UserDefaults plugin shows, as a value: the suites offered, the one shown,
    /// its keys as last read, and the filters.
    ///
    /// ``UserDefaultsModel`` makes it; the plugin's view draws it. It is `Codable`, so a transport
    /// can carry it.
    public struct UserDefaultsSnapshot: Codable, Equatable, Sendable {
        /// Standard first, then each suite the host named, in its order.
        var suites: [UserDefaultsSuite] = [.standard]
        /// The suite whose keys show.
        var selectedSuite = UserDefaultsSuite.standard
        /// The shown suite's keys, sorted, as last read: the persistent domain's, then each key
        /// only another domain holds, from the domain whose value the suite reads. Empty until read.
        var entries: [DefaultsEntry] = []
        /// What a key or its value must contain to show, ignoring case; empty shows every key.
        var searchText = ""
        /// Whether keys only the argument, global or registration domain holds show, read-only.
        var showOtherDomains = false

        /// The entries the filters let through: unless other domains show, only the persistent
        /// domain's, and only those whose key or value contains the search text, ignoring case.
        var filteredEntries: [DefaultsEntry] {
            let shown = showOtherDomains ? entries : entries.filter { $0.domain == .persistent }
            guard !searchText.isEmpty else { return shown }
            return shown.filter { $0.matches(searchText) }
        }

        /// The keys of the shown suite's persistent domain, which a new key mustn't be.
        var persistentKeys: Set<String> {
            Set(entries.lazy.filter { $0.domain == .persistent }.map(\.key))
        }
    }

    extension DefaultsEntry {
        /// Whether the key or the value as shown contains `text`, ignoring case.
        fileprivate func matches(_ text: String) -> Bool {
            key.localizedCaseInsensitiveContains(text) || value.summary.localizedCaseInsensitiveContains(text)
        }
    }
#else
    /// Release builds read no defaults: this stand-in holds nothing.
    public struct UserDefaultsSnapshot: Codable, Equatable, Sendable {}
#endif
