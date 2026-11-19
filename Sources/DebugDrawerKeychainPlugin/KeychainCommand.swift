import Foundation

// Public because it is `KeychainModel`'s `Command`, and opaque: an enum's cases share its access
// level, and an item's identity and the form's values are the plugin's own types, so the public
// type is a struct around the internal enum. Items are named by their persistent reference, the
// handle the keychain reads and changes them by. Copy isn't one: it reads the snapshot and writes
// the clipboard, which is the view's.

#if DEBUG
    /// Something the Keychain plugin's view asks ``KeychainModel`` to do: read the keychain again,
    /// filter, open an item to reveal its password, add or edit a generic password, delete an item
    /// or every item the filter shows. `Codable`, so a transport can carry it.
    public struct KeychainCommand: Codable, Sendable {
        /// What to do.
        enum Action: Codable, Equatable, Sendable {
            /// Reads the items again, keeping the open item open if it is still there.
            case reload
            /// Shows only the items the filter lets through.
            case setFilter(KeychainFilter)
            /// Opens the item's detail, reading its password, or closes it if it is open.
            case toggle(KeychainItem.ID)
            /// Opens the form to add a generic password, in the group the filter shows.
            case startAdding
            /// Opens the form to edit the item from its values and password, or reports why the
            /// password can't be read.
            case startEditing(KeychainItem.ID)
            /// Closes the form without saving.
            case cancelEditing
            /// Adds the password, or rewrites the item being edited, then reads the items again.
            case save(GenericPassword)
            /// Deletes the item alone, then reads the items again.
            case delete(KeychainItem.ID)
            /// Deletes every item the filter shows as the command is performed, each alone, then
            /// reads the items again.
            case deleteShown
        }

        let action: Action

        init(_ action: Action) {
            self.action = action
        }
    }
#else
    /// Release builds read no keychain: this stand-in asks for nothing.
    public struct KeychainCommand: Codable, Sendable {}
#endif
