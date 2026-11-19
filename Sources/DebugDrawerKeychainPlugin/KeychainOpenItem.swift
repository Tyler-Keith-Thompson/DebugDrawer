#if DEBUG
    /// The item whose detail is open, as the snapshot carries it: its metadata and whether its
    /// password was read, never the password itself.
    struct KeychainOpenItem: Codable, Hashable, Sendable {
        let item: KeychainItem
        /// Whether the password was read and is held in the process, holds none, or was refused.
        let value: KeychainValueState
    }

    /// What became of reading an open item's password, without the password.
    enum KeychainValueState: Codable, Hashable, Sendable {
        /// Read, and held in the app's process alone: `KeychainModel.revealedValue(for:)` returns it
        /// there, and no snapshot or transport carries it.
        case held
        /// The item holds no password, as a certificate or a key doesn't.
        case empty
        /// The keychain refused to give it.
        case refused(KeychainError)
    }

    extension KeychainOpenItem {
        /// `selection` without its password.
        init(_ selection: KeychainSelection) {
            let value: KeychainValueState = switch selection.value {
            case .success(.some): .held
            case .success(.none): .empty
            case let .failure(error): .refused(error)
            }
            self.init(item: selection.item, value: value)
        }
    }
#endif
