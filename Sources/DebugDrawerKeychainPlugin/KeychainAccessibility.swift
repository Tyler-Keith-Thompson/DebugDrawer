#if DEBUG
    import Security

    /// When an item can be read (`kSecAttrAccessible`), as the add and edit form offers it.
    enum KeychainAccessibility: CaseIterable, Hashable, Identifiable, Sendable {
        case whenUnlocked
        case afterFirstUnlock
        case whenUnlockedThisDeviceOnly
        case afterFirstUnlockThisDeviceOnly
        case whenPasscodeSetThisDeviceOnly

        var id: Self {
            self
        }

        /// The `kSecAttrAccessible` value.
        var secValue: CFString {
            switch self {
            case .whenUnlocked: kSecAttrAccessibleWhenUnlocked
            case .afterFirstUnlock: kSecAttrAccessibleAfterFirstUnlock
            case .whenUnlockedThisDeviceOnly: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            case .afterFirstUnlockThisDeviceOnly: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            case .whenPasscodeSetThisDeviceOnly: kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly
            }
        }

        /// The constant's name less its `kSecAttrAccessible` prefix, as Apple's documentation
        /// names the classes.
        var title: String {
            switch self {
            case .whenUnlocked: "WhenUnlocked"
            case .afterFirstUnlock: "AfterFirstUnlock"
            case .whenUnlockedThisDeviceOnly: "WhenUnlockedThisDeviceOnly"
            case .afterFirstUnlockThisDeviceOnly: "AfterFirstUnlockThisDeviceOnly"
            case .whenPasscodeSetThisDeviceOnly: "WhenPasscodeSetThisDeviceOnly"
            }
        }

        /// The class a `kSecAttrAccessible` value names, or `nil` for one the plugin doesn't know.
        init?(secValue: String) {
            guard let match = Self.allCases.first(where: { $0.secValue as String == secValue }) else { return nil }
            self = match
        }
    }
#endif
