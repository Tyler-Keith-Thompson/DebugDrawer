#if DEBUG
    import Foundation

    /// A generic password as the add and edit form writes it.
    struct GenericPassword: Codable, Hashable, Sendable {
        var service = ""
        var account = ""
        /// The item's label; empty for none.
        var label = ""
        /// The password, written as UTF-8.
        var value = ""
        /// The access group to add it to; `nil` for the app's default group. An edit leaves an
        /// item in the group it is in.
        var accessGroup: String?
        var accessibility = KeychainAccessibility.whenUnlocked

        /// Whether the password can be written: it needs a service or an account to be found by.
        var isSavable: Bool {
            !service.isEmpty || !account.isEmpty
        }
    }

    extension GenericPassword {
        /// The form's starting point for editing `item`, whose password is `value`.
        init(editing item: KeychainItem, value: Data?) {
            self.init(
                service: item.service,
                account: item.account,
                label: item.label ?? "",
                value: value.flatMap { String(data: $0, encoding: .utf8) } ?? "",
                accessGroup: item.accessGroup,
                accessibility: item.accessibility ?? .whenUnlocked
            )
        }
    }
#endif
