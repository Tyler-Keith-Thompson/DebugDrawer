import Foundation

// Public because it is `UserDefaultsModel`'s `Command`, and opaque: an enum's cases share its
// access level, and suites and values are the plugin's own types, so the public type is a struct
// around the internal enum. Copy Value isn't one: it reads the snapshot and writes the clipboard,
// which is the view's. Nor is resetting a key to its registered default: removing the app's value
// does that, as UserDefaults then reads the registration domain's.

#if DEBUG
    /// Something the UserDefaults plugin's view asks ``UserDefaultsModel`` to do: pick a suite,
    /// filter its keys, write, add or remove a key, read the suite again, or follow the app's
    /// writes while shown. `Codable`, so a transport can carry it.
    public struct UserDefaultsCommand: Codable, Sendable {
        /// What to do.
        enum Action: Codable, Equatable, Sendable {
            /// Shows the suite's keys, read now. A suite the model doesn't offer is ignored.
            case selectSuite(UserDefaultsSuite)
            /// Shows only the keys whose key or value contains the text, ignoring case.
            case setSearchText(String)
            /// Shows, or hides, keys only the argument, global or registration domain holds.
            case setShowOtherDomains(Bool)
            /// Writes the whole value for the key in the shown suite's persistent domain, then
            /// reads the suite again.
            case set(PropertyListValue, forKey: String)
            /// Adds the key to the shown suite with a value of the type: empty, zero, false, or for
            /// a date, now.
            case add(String, type: PropertyListType)
            /// Removes the key from the shown suite's persistent domain; a value another domain
            /// holds for it then shows.
            case remove(String)
            /// Reads the shown suite again.
            case reload
            /// Reads the suite, then again after each change the app makes, until balanced by
            /// `stopObserving`: each view that shows the keys sends it as it appears.
            case startObserving
            /// Balances one `startObserving`, as a view disappears; after the last, the app's
            /// changes are no longer read.
            case stopObserving
        }

        let action: Action

        init(_ action: Action) {
            self.action = action
        }
    }
#else
    /// Release builds read no defaults: this stand-in asks for nothing.
    public struct UserDefaultsCommand: Codable, Sendable {}
#endif
