import Foundation

// Public because it is `KeychainModel`'s `Snapshot`, and opaque: its fields stay internal, so a
// reader outside the module carries it whole, encoded. It holds the items as values read from the
// keychain (their class, persistent reference, attributes as text and dates; never a SecKey,
// SecCertificate or other CF type), the filter, the open item with its password as `Data`, the
// form's starting values and the last refusal. Which items the filter shows and the access groups
// are worked out from them; the view words and formats all of it.

#if DEBUG
    /// Everything the Keychain plugin shows, as a value: the items, once read, the filter, the open
    /// item with its password, the add or edit form and the last change the keychain refused.
    ///
    /// ``KeychainModel`` makes it; the plugin's view draws it. It is `Codable`, so a transport can
    /// carry it.
    public struct KeychainSnapshot: Codable, Equatable, Sendable {
        /// The items read, that none are yet, or why the keychain can't be read.
        var contents = KeychainContents.unread
        /// Which items the list shows.
        var filter = KeychainFilter()
        /// The item whose detail is open, with its password.
        var selection: KeychainSelection?
        /// The add or edit form, while it is open.
        var editor: KeychainEditor?
        /// The last change the keychain refused.
        var issue: KeychainIssue?

        /// Every item read, in class order.
        var allItems: [KeychainItem] {
            guard case let .items(items) = contents else { return [] }
            return items
        }

        /// The items the filter lets through.
        var shownItems: [KeychainItem] {
            filter.apply(to: allItems)
        }

        /// The access groups of every item, for the filter to choose from.
        var accessGroups: [String] {
            allItems.accessGroups
        }
    }
#else
    /// Release builds read no keychain: this stand-in holds nothing.
    public struct KeychainSnapshot: Codable, Equatable, Sendable {}
#endif
