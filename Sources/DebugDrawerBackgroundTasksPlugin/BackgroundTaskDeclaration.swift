#if DEBUG
    /// What the Info.plist declares for background tasks: the identifiers `BGTaskScheduler`
    /// accepts requests for, and the kinds of request its background modes let it run.
    struct BackgroundTaskDeclaration: Equatable, Sendable {
        /// The Info.plist key that lists the permitted identifiers.
        static let permittedIdentifiersKey = "BGTaskSchedulerPermittedIdentifiers"
        /// The Info.plist key that lists the background modes.
        static let backgroundModesKey = "UIBackgroundModes"

        /// The permitted identifiers, in the Info.plist's order.
        let identifiers: [PermittedIdentifier]
        /// The kinds the background modes allow, in `BackgroundTaskKind`'s order: app refresh
        /// for `fetch`, processing for `processing`. The system refuses a request of any other.
        let kinds: [BackgroundTaskKind]

        init(identifiers: [PermittedIdentifier], kinds: [BackgroundTaskKind]) {
            self.identifiers = identifiers
            self.kinds = kinds
        }

        /// Reads `infoDictionary`'s permitted identifiers, dropping any entry that isn't a
        /// non-empty string and every repeat of one already listed, and its background modes.
        /// A missing key, or one that isn't an array, lists nothing.
        ///
        /// - Parameter infoDictionary: An Info.plist's contents, as `Bundle.infoDictionary` has them.
        init(infoDictionary: [String: Any]) {
            var seen = Set<String>()
            let listed = (infoDictionary[Self.permittedIdentifiersKey] as? [Any] ?? []).compactMap { $0 as? String }
            identifiers = listed.filter { !$0.isEmpty && seen.insert($0).inserted }.map(PermittedIdentifier.init)
            let modes = Set((infoDictionary[Self.backgroundModesKey] as? [Any] ?? []).compactMap { $0 as? String })
            kinds = BackgroundTaskKind.allCases.filter { modes.contains($0.backgroundMode) }
        }
    }
#endif
