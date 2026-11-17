#if DEBUG
    import Foundation

    /// The entitlements the app runs with, in the order App Info lists them: the common ones by
    /// name first, associated domains at the top, then the rest by key.
    struct Entitlements: Equatable {
        /// Where the entitlements were read.
        enum Source: Equatable {
            /// The app's code signature, as on the Mac.
            case codeSignature
            /// The `__TEXT,__entitlements` section linked into the executable, as a simulator
            /// build has them.
            case executable
            /// The provisioning profile's `Entitlements`, as on a device: what the profile allows,
            /// which the app's signature may narrow.
            case provisioningProfile
        }

        var source: Source
        /// The entitlements, in display order; empty when the app has none.
        var entries: [Entitlement]

        /// The entitlements of a dictionary as code signatures and profiles hold them.
        init(dictionary: [String: Any], source: Source) {
            self.source = source
            entries = dictionary
                .map { Entitlement(key: $0.key, value: Entitlement.Value($0.value)) }
                .sorted { $0.precedes($1) }
        }

        init(source: Source, entries: [Entitlement]) {
            self.source = source
            self.entries = entries
        }
    }
#endif
