#if DEBUG
    /// The add and edit form, while it is open.
    enum KeychainEditor: Codable, Hashable, Sendable {
        /// Adding a generic password, starting from the values given.
        case adding(GenericPassword)
        /// Editing `item`, starting from its values.
        case editing(KeychainItem, GenericPassword)

        /// What the form starts from.
        var draft: GenericPassword {
            switch self {
            case let .adding(draft), let .editing(_, draft): draft
            }
        }
    }
#endif
