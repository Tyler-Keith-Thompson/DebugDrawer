#if DEBUG
    import DebugDrawer
    import SwiftUI

    public struct NetworkPlugin: DebugDrawerPlugin {
        public var title = "Network"
        public var category = "Logs & Network"
        public var icon = "network"

        public init() {}

        public var body: some View {
            NetworkPluginView()
        }

        /// How many requests were captured, and how many of them failed; the conditions that are
        /// on, when any are.
        public var headerAccessory: some View {
            NetworkHeaderAccessoryView()
        }

        /// The conditions that are on ("3G active"), so they show with the drawer closed.
        @MainActor public var hud: NetworkConditionsHUD? {
            NetworkConditionsHUD(conditions: .shared)
        }
    }

    public extension DebugDrawer {
        /// Install the network inspector. Registers a URLProtocol to capture HTTP traffic, and
        /// loads the saved mock rules, which answer the requests they match from then on, and the
        /// saved conditioning profiles, which slow down or fail the requests to their hosts, and
        /// the saved ignore list, whose hosts' requests the log hides.
        ///
        /// - Parameters:
        ///   - mocks: Rules to add to the saved ones, at the end; one whose id is saved already is
        ///     skipped, so the drawer's edits to it last from launch to launch.
        ///   - conditions: Profiles to add to the saved ones, at the end, by id as `mocks` are.
        ///   - ignoring: Hosts or domains to add to the saved ignore list (`"analytics.example.com"`),
        ///     whose requests, and their subdomains', the log hides until shown. One the list holds
        ///     already is skipped, and one that isn't a host is logged and skipped.
        ///   - sessions: How many earlier launches' requests are kept on disk, in how many bytes,
        ///     and where; each request is written, redacted, as it completes, and the log shows
        ///     the earlier sessions under Previous. ``NetworkSessionPersistence/off`` writes none.
        func installNetwork(
            mocks: [NetworkMockRule] = [],
            conditions: [NetworkConditionProfile] = [],
            ignoring: [String] = [],
            sessions: NetworkSessionPersistence = .standard
        ) {
            NetworkMocksModel.shared.load(adding: mocks)
            NetworkConditionsModel.shared.load(adding: conditions)
            NetworkStore.shared.loadIgnoreList(adding: ignoring.compactMap(NetworkIgnoredDomain.seed))
            // Started before the URL protocol is registered, so the first request is written too,
            // and once a launch, so a second install doesn't start a second session.
            if NetworkStore.shared.recorder == nil {
                let recorder = NetworkSessionRecorder(sessions)
                NetworkStore.shared.persist(to: recorder)
                Task { await NetworkSessionsModel.shared.start(recorder) }
            }
            NetworkStore.shared.install()
            registerGlobal(NetworkPlugin())
        }
    }
#endif
