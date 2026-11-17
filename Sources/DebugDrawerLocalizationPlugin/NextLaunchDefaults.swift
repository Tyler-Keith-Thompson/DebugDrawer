#if DEBUG
    import Foundation

    /// The ``NextLaunchOption``s stored in the app's own defaults domain, where Foundation reads
    /// them at launch.
    ///
    /// Only the persistent domain counts: an option passed as a launch argument applies too, but
    /// isn't stored, so turning it off here can't remove it, and it isn't shown as stored.
    struct NextLaunchDefaults {
        /// Where the options are written: the app's `UserDefaults.standard`, or a suite in tests.
        let defaults: UserDefaults
        /// The name of the persistent domain `defaults` writes to: the app's bundle identifier,
        /// or the suite's name.
        let domainName: String

        /// The app's own defaults; `nil` for a process with no bundle identifier, which has no
        /// domain of its own to store them in.
        static var standard: NextLaunchDefaults? {
            Bundle.main.bundleIdentifier.map { NextLaunchDefaults(defaults: .standard, domainName: $0) }
        }

        /// The options whose every key is stored as `true`.
        func stored() -> Set<NextLaunchOption> {
            let domain = defaults.persistentDomain(forName: domainName) ?? [:]
            return Set(NextLaunchOption.allCases.filter { option in
                option.defaultsKeys.allSatisfy { (domain[$0] as? Bool) == true }
            })
        }

        /// Stores `option`'s keys as `true`, or removes them.
        func set(_ option: NextLaunchOption, isOn: Bool) {
            for key in option.defaultsKeys {
                if isOn {
                    defaults.set(true, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
    }
#endif
