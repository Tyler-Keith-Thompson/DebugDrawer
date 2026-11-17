#if DEBUG
    /// Which items the list shows: those in one access group, or every group's, whose account,
    /// service or label contains the text.
    struct KeychainFilter: Hashable, Sendable {
        /// Text to look for, ignoring case; empty matches every item.
        var text = ""
        /// The access group to show; `nil` for every group.
        var accessGroup: String?

        /// The items of `items` that match, in their order.
        func apply(to items: [KeychainItem]) -> [KeychainItem] {
            items.filter(matches)
        }

        private func matches(_ item: KeychainItem) -> Bool {
            if let accessGroup, item.accessGroup != accessGroup { return false }
            guard !text.isEmpty else { return true }
            return [item.account, item.service, item.label ?? ""].contains { $0.localizedCaseInsensitiveContains(text) }
        }
    }

    extension [KeychainItem] {
        /// The access groups the items belong to, each once, sorted.
        var accessGroups: [String] {
            Set(compactMap(\.accessGroup)).sorted()
        }
    }
#endif
