#if DEBUG
    /// Where a suite finds a key's value, named as `UserDefaults` names its domains.
    enum DefaultsDomain: CaseIterable {
        /// What the app wrote: the standard defaults' domain, named by the bundle identifier, or a
        /// named suite's own. The only domain the plugin edits.
        case persistent
        /// The launch arguments' (`-key value`), which override the persistent domain.
        case argument
        /// Every app's: the global domain, for this host and for any, which the system writes.
        case global
        /// The fallbacks the app registered with `register(defaults:)`, kept in memory only.
        case registration

        /// The domain as a row names it; `nil` for the persistent domain, which is the norm.
        var title: String? {
            switch self {
            case .persistent: nil
            case .argument: "Argument"
            case .global: "Global"
            case .registration: "Registered"
            }
        }

        /// Why a value from the domain can't be edited or deleted here; `nil` for the persistent
        /// domain, which can.
        var readOnlyReason: String? {
            switch self {
            case .persistent: nil
            case .argument: "Read-only: a launch argument sets this key until the app launches without it."
            case .global: "Read-only: the system's global domain holds this key for every app."
            case .registration: "Read-only: the app registers this default each launch. Add the key to override it."
            }
        }
    }
#endif
