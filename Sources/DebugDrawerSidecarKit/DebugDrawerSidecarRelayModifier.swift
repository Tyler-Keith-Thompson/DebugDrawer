#if canImport(DebugDrawerRemote)
    import DebugDrawerRemote
    import SwiftUI

    // How a sidecar app turns the device-lab relay on: a modifier on its `DebugDrawerSidecarView`
    // (or any view above the kit's screens), which puts the relay's settings in the environment.
    // Without it the kit makes no relay, so nothing listens and nothing is relayed: the bridge is
    // off until the sidecar app asks for it. A modifier rather than a parameter of the view's
    // initializers, so the three initializers stay as they are and a sidecar that never relays
    // names nothing of the network transport.

    /// Whether the kit relays the app picked to a Mac viewer, and how it listens.
    struct SidecarRelaySettings: Equatable {
        /// Where the relay's server listens, and whether it advertises.
        let configuration: DebugDrawerNetworkServerConfiguration
        /// Whether it starts listening as the app's screen appears, rather than when the person
        /// asks.
        let startsServing: Bool
    }

    extension EnvironmentValues {
        /// The relay's settings, when the sidecar app turned it on; `nil` makes no relay.
        @Entry var sidecarRelaySettings: SidecarRelaySettings?
    }

    extension View {
        /// Lets the person holding the sidecar share the app picked with a Mac viewer: the app's
        /// screen gets a Mac Viewer control, which listens for viewers (a
        /// ``DebugDrawerSidecarRelay`` for the app), shows each one's pairing code, and relays the
        /// capabilities the open session may read to a viewer once paired, for as long as the
        /// session lasts.
        ///
        /// ```swift
        /// DebugDrawerSidecarView(groupIdentifier: "TEAMID.com.example.debug", plugins: [.featureFlagOverrides])
        ///     .debugDrawerSidecarRelay()
        /// ```
        ///
        /// Without it nothing listens. On iOS the sidecar app's Info.plist needs
        /// `NSLocalNetworkUsageDescription` and `_debugdrawer._tcp` in `NSBonjourServices`; a
        /// sandboxed Mac sidecar needs the `com.apple.security.network.server` entitlement.
        /// Release builds return the view unchanged.
        ///
        /// - Parameters:
        ///   - configuration: Where to listen, and whether to advertise over Bonjour.
        ///   - startsServing: Whether to listen as soon as an app is picked, for a lab device
        ///     whose sidecar always shares; otherwise the person starts it.
        /// - Returns: The view, relaying when asked.
        public func debugDrawerSidecarRelay(
            _ configuration: DebugDrawerNetworkServerConfiguration = .init(),
            startsServing: Bool = false
        ) -> some View {
            #if DEBUG
                environment(\.sidecarRelaySettings, SidecarRelaySettings(configuration: configuration, startsServing: startsServing))
            #else
                self
            #endif
        }
    }
#endif
