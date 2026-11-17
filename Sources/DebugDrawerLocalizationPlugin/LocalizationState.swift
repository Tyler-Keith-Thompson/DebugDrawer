#if DEBUG
    import Foundation
    import os

    /// What the intercepted lookups read and write: the mode, which bundles are the app's, and the
    /// keys looked up with no translation.
    ///
    /// Lookups run on any thread and must return at once, so the state sits behind a lock rather
    /// than in an actor, which no synchronous lookup could wait for. `OSAllocatedUnfairLock`
    /// rather than `Mutex`, which needs iOS 18; switch to `Mutex` once iOS 18 is the minimum.
    final class LocalizationState: Sendable {
        /// The state the installed interception reads, for the life of the app.
        static let shared = LocalizationState(appBundles: .main)

        /// How many untranslated lookups are kept; later ones are dropped, so an app that looks
        /// up generated keys can't grow the list without bound.
        static let lookupCapacity = 1000

        fileprivate struct Storage: Sendable {
            var mode: Localization.Mode = .standard
            var appBundles: AppBundles
            /// The untranslated lookups, in the order first seen, each once.
            var lookups: [LocalizationLookup] = []
            var seen: Set<LocalizationLookup> = []
            /// Whether a change has been reported that ``lookups`` hasn't been read since, so a
            /// burst of lookups is one reload.
            var isChangeReported = false
            var onChange: (@Sendable () -> Void)?
        }

        private let storage: OSAllocatedUnfairLock<Storage>

        init(appBundles: AppBundles) {
            storage = OSAllocatedUnfairLock(initialState: Storage(appBundles: appBundles))
        }

        /// What the app's strings show.
        var mode: Localization.Mode {
            get { storage.withLock(\.mode) }
            set { storage.withLock { $0.mode = newValue } }
        }

        /// Which bundles are the app's.
        var appBundles: AppBundles {
            get { storage.withLock(\.appBundles) }
            set { storage.withLock { $0.appBundles = newValue } }
        }

        /// The mode, if the bundle at `path` is the app's; `nil` for any other bundle, whose
        /// strings are left alone.
        func mode(forBundleAt path: String) -> Localization.Mode? {
            storage.withLock { $0.appBundles.contains(path) ? $0.mode : nil }
        }

        /// Keeps an untranslated lookup, unless it is kept already or the list is full, and
        /// reports the change unless one is already waiting to be read.
        func record(_ lookup: LocalizationLookup) {
            let onChange = storage.withLock { storage -> (@Sendable () -> Void)? in
                guard storage.lookups.count < Self.lookupCapacity, storage.seen.insert(lookup).inserted else { return nil }
                storage.lookups.append(lookup)
                guard !storage.isChangeReported, let onChange = storage.onChange else { return nil }
                storage.isChangeReported = true
                return onChange
            }
            // Outside the lock: the observer may read the lookups.
            onChange?()
        }

        /// The untranslated lookups, in the order first seen. Reading them lets the next change be
        /// reported.
        var lookups: [LocalizationLookup] {
            storage.withLock { storage in
                storage.isChangeReported = false
                return storage.lookups
            }
        }

        /// Calls `onChange` after a lookup is recorded, from the thread that looked it up, until
        /// ``lookups`` is read; then again on the next. Replaces the observer before it.
        func observe(_ onChange: @escaping @Sendable () -> Void) {
            storage.withLock { storage in
                storage.onChange = onChange
                storage.isChangeReported = false
            }
        }
    }
#endif
