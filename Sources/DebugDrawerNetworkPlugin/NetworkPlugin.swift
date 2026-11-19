import DebugDrawer
import SwiftUI

// The public API compiles in every configuration; the implementation under `#if DEBUG` in the
// module's other files does not, so release builds get empty views and an installer that
// intercepts and registers nothing.

public struct NetworkPlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer, which its saved state, HUD pin and badges are kept under.
    public nonisolated var id: String {
        "NetworkPlugin"
    }

    public var title = "Network"
    public var category = "Logs & Network"
    public var icon = "network"

    public init() {}

    public var body: some View {
        #if DEBUG
            NetworkPluginView(transport: .direct(to: NetworkModel.shared))
        #else
            EmptyView()
        #endif
    }

    /// How many requests were captured, and how many of them failed; the conditions that are
    /// on, when any are.
    public var headerAccessory: some View {
        #if DEBUG
            NetworkHeaderAccessoryView(transport: .direct(to: NetworkModel.shared))
        #else
            EmptyView()
        #endif
    }

    /// The conditions that are on ("3G active"), so they show with the drawer closed; none in
    /// release builds.
    @MainActor public var hud: NetworkConditionsHUD? {
        #if DEBUG
            NetworkConditionsHUD(transport: .direct(to: NetworkModel.shared))
        #else
            nil
        #endif
    }

    /// Starts capturing (``NetworkStore/install()``) as `drawer` adds the plugin. Release
    /// builds capture nothing.
    @MainActor public func install(in drawer: DebugDrawer) {
        #if DEBUG
            NetworkInterception.install(for: drawer)
        #endif
    }

    /// Stops capturing and forgets the captured requests (``NetworkStore/uninstall()``) once
    /// no drawer holds the plugin: the URL protocol is unregistered and every replaced method
    /// gets its original implementation back.
    @MainActor public func uninstall(from drawer: DebugDrawer) {
        #if DEBUG
            NetworkInterception.uninstall(for: drawer)
        #endif
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
    ///   - bypassing: Hosts or domains the plugin leaves alone (`"api.example.com"`), such as
    ///     those whose certificates the app pins. Their requests, and their subdomains', never
    ///     reach the plugin's URL protocol: the app's session sends them as it would without the
    ///     plugin, and only its delegate sees their TLS challenges. The plugin doesn't log, mock,
    ///     condition or resend them, and doesn't record their WebSocket tasks. Replaces the hosts
    ///     an earlier call bypassed. Traps on one that isn't a host, so a typo can't let the
    ///     plugin take requests the app meant to keep out.
    ///   - sessions: How many earlier launches' requests are kept on disk, in how many bytes,
    ///     and where; each request is written, redacted, as it completes, and the log shows
    ///     the earlier sessions under Previous. ``NetworkSessionPersistence/off`` writes none.
    ///   - bodyLimit: The most bytes of each request and response body the log keeps, 1 MiB
    ///     unless given. A larger body is kept to its first `bodyLimit` bytes and marked
    ///     truncated, with its full size, so a large upload, download or stream costs the log no
    ///     more; the server and the app still get every byte. Applies to the requests that start
    ///     after the call. Traps when negative.
    func installNetwork(
        mocks: [NetworkMockRule] = [],
        conditions: [NetworkConditionProfile] = [],
        ignoring: [String] = [],
        bypassing: [String] = [],
        sessions: NetworkSessionPersistence = .standard,
        bodyLimit: Int = 1_048_576
    ) {
        #if DEBUG
            precondition(bodyLimit >= 0, "installNetwork(bodyLimit:) can't be negative")
            // Before the URL protocol is registered, so no request to a bypassed host is taken.
            NetworkBypass.bypass(bypassing)
            NetworkBodyCapture.limit.withLock { $0 = bodyLimit }
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
            // Adding the plugin installs it, which starts capturing.
            registerGlobal(NetworkPlugin())
        #endif
    }
}
