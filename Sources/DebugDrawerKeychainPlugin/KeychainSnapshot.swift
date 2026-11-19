import Foundation

// Public because it is `KeychainModel`'s `Snapshot`, and opaque: its fields stay internal, so a
// reader outside the module carries it whole, encoded. It holds the items as values read from the
// keychain (their class, persistent reference, attributes as text and dates; never a SecKey,
// SecCertificate or other CF type), the filter, which item is open and whether its password was
// read, the form's starting values and the last refusal. It never holds a password: a transport
// may carry it out of the app, so the open item's password and the edit form's starting one stay
// in the process, read through `KeychainModel.revealedValue(for:)`. Which items the filter shows
// and the access groups are worked out from it; the view words and formats all of it.

#if DEBUG
    /// Everything the Keychain plugin shows but the passwords, as a value: the items, once read,
    /// the filter, the open item, the add or edit form and the last change the keychain refused.
    ///
    /// ``KeychainModel`` makes it; the plugin's view draws it. It is `Codable`, so a transport can
    /// carry it.
    public struct KeychainSnapshot: Codable, Equatable, Sendable {
        /// The items read, that none are yet, or why the keychain can't be read.
        var contents = KeychainContents.unread
        /// Which items the list shows.
        var filter = KeychainFilter()
        /// The item whose detail is open, and whether its password was read.
        var selection: KeychainOpenItem?
        /// The add or edit form, while it is open, its password always empty.
        var editor: KeychainEditor?
        /// The last change the keychain refused.
        var issue: KeychainIssue?

        /// A snapshot holding `editor` with its password emptied, so no snapshot holds one.
        init(
            contents: KeychainContents = .unread,
            filter: KeychainFilter = KeychainFilter(),
            selection: KeychainOpenItem? = nil,
            editor: KeychainEditor? = nil,
            issue: KeychainIssue? = nil
        ) {
            self.contents = contents
            self.filter = filter
            self.selection = selection
            self.editor = editor?.starting(withValue: "")
            self.issue = issue
        }

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
