import DebugDrawer
#if canImport(DebugDrawerConsolePlugin)
    import DebugDrawerConsolePlugin
#endif
#if canImport(DebugDrawerNetworkPlugin)
    import DebugDrawerNetworkPlugin
#endif
import SwiftUI

// A plugin the sidecar can show: the ID its model is served under in the app, and how to make the
// plugin over a transport to that model. The plugin is a `DebugDrawerPlugin` like any other, so the
// kit draws its body and header accessory as the drawer would, and puts it in the bug report through
// `DebugDrawerReportContributor`, without knowing its types. Console and Network ship here, as
// they are the plugins every sidecar wants, and so does a view of every capability the receiver
// ships (one file each, `Sidecar<Capability>Plugin.swift`), over the capability's UI-free module, so
// no company writes its own; any other plugin whose model adopts `DebugDrawerPluginModel` comes in
// through the generic initializer, from a module the host links.
//
// Rejected: a protocol in core that plugins adopt to be hosted (a plugin's model ID is only known
// from an instance, and core would grow a second plugin contract for one caller); the kit depending
// on every drawer plugin with a model (a sidecar would link them all, the N5 shape; the capability
// modules it depends on are UI-free and small); a sidecar-view product per capability (every
// sidecar links them all anyway); and the host writing a view per plugin (the plugins' own views
// over a transport already exist).
//
// Console and Network are linked only where they build (PLATFORM_CONDITIONAL_DEPENDENCIES in
// scripts/modules.py): not on watchOS, where the kit hosts the receiver's plugins alone, so a watch
// sidecar names the plugins it shows. Checked with canImport rather than os(watchOS), so the kit
// gains them on a platform as soon as they are ported there.

/// A plugin a sidecar shows for an app, drawn from the app's model of it over the sidecar's
/// transport.
///
/// ```swift
/// DebugDrawerSidecarView(groupIdentifier: "TEAMID.com.example.debug", plugins: [.console, .network])
/// ```
///
/// ``console`` and ``network`` show the Console and Network plugins, on macOS and iOS: watchOS
/// doesn't build them. Each capability the receiver ships has its own, named for the capability
/// (``featureFlagOverrides``, ``tweaks``, ``logLevels``, …). Any plugin whose model the app
/// serves comes in through ``init(id:title:icon:snapshot:command:plugin:)``, with the plugin made
/// over the transport.
public struct DebugDrawerSidecarPlugin: Identifiable {
    /// The ID the app serves the plugin's model under.
    public let id: String
    /// The plugin's name, as the sidecar lists it.
    public let title: String
    /// The plugin's SF Symbol name.
    public let icon: String
    /// Connects to the model over a transport and makes the plugin over it, keeping each
    /// snapshot in the cache, when one is given.
    let connect: @MainActor (any DebugDrawerTransport, SidecarSnapshotCache?) async throws(DebugDrawerTransportError) -> AnyDebugDrawerPlugin
    /// Makes the plugin over the sidecar's transport from the snapshot the cache kept, calling
    /// the closure as the app serves the model again; `nil` when the cache keeps none.
    let prepare: @MainActor (DebugDrawerSidecarTransport, SidecarSnapshotCache, @escaping @MainActor () -> Void) -> AnyDebugDrawerPlugin?
    /// Whether the sidecar view hosts it as soon as the app is reached rather than when it is
    /// picked, so its report contribution is in every report: the app state's.
    var hostsOnConnect = false
    /// Whether the sidecar keeps its snapshots, so it can be prepared before the app launches:
    /// `false` for the plugins that show what the app collects while it runs (logs, requests,
    /// events, payloads, reports), which hold nothing to prepare and change too often to copy.
    var preparesForLaunch = true

    /// A plugin whose model the app serves under `id`, made over the transport to it.
    ///
    /// ```swift
    /// let tweaks = DebugDrawerSidecarPlugin(
    ///     id: "MyApp.LogLevels", title: "Log Levels", icon: "slider.horizontal.3",
    ///     snapshot: LogLevelsModel.Snapshot.self, command: LogLevelsModel.Command.self
    /// ) { transport in
    ///     LogLevelsPlugin(transport: transport)
    /// }
    /// ```
    ///
    /// - Parameters:
    ///   - id: The ID the app registered or enabled the model under.
    ///   - title: The plugin's name, as the sidecar lists it.
    ///   - icon: An SF Symbol name.
    ///   - snapshot: The model's `Snapshot` type.
    ///   - command: The model's `Command` type.
    ///   - plugin: Makes the plugin over the transport to the model; its `body` is what the
    ///     sidecar shows, and its report contribution, if it adopts `DebugDrawerReportContributor`,
    ///     goes in the sidecar's bug report.
    public init<Snapshot: Codable & Equatable & Sendable, Command: Codable & Sendable, Plugin: DebugDrawerPlugin>(
        id: String,
        title: String,
        icon: String,
        snapshot: Snapshot.Type,
        command: Command.Type,
        plugin: @escaping @MainActor (DebugDrawerPluginTransport<Snapshot, Command>) -> Plugin
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        connect = { transport, cache throws(DebugDrawerTransportError) in
            let connected = try await transport.connect(toPlugin: id, snapshot: snapshot, command: command)
            cache?.follow(connected, as: id)
            return AnyDebugDrawerPlugin(plugin(connected))
        }
        prepare = { transport, cache, live in
            #if DEBUG
                guard let initial = cache.snapshot(of: id, as: snapshot),
                      let prepared = transport.prepare(toPlugin: id, snapshot: snapshot, command: command, from: initial, live: live)
                else { return nil }
                cache.follow(prepared, as: id)
                return AnyDebugDrawerPlugin(plugin(prepared))
            #else
                // Release builds connect to nothing, so nothing is prepared.
                return nil
            #endif
        }
    }

    /// The plugin over a transport of the caller's, once the model's first snapshot arrives: for a
    /// viewer outside the sidecar's own screens, such as a Mac showing what a sidecar relays
    /// (``DebugDrawerSidecarRelay``) over a `DebugDrawerNetworkTransport`.
    ///
    /// ```swift
    /// let flags = try await DebugDrawerSidecarPlugin.featureFlagOverrides.plugin(over: viewer)
    /// ```
    ///
    /// It waits while the model's side serves no snapshot of it.
    ///
    /// - Parameter transport: The connection to the models' side.
    /// - Returns: The plugin, ready to draw.
    /// - Throws: What the transport's `connect` throws: `mismatchedTypes` when the model under
    ///   ``id`` has other types, `disconnected` and `cancelled`.
    @MainActor public func plugin(over transport: any DebugDrawerTransport) async throws(DebugDrawerTransportError) -> AnyDebugDrawerPlugin {
        try await connect(transport, nil)
    }

    /// The plugin, marked as one that shows only what the app collects while it runs, so it is
    /// never prepared before launch and its snapshots aren't kept.
    func collectedWhileRunning() -> DebugDrawerSidecarPlugin {
        var plugin = self
        plugin.preparesForLaunch = false
        return plugin
    }

    /// The plugins a sidecar shows unless it names its own: Console and Network where they build,
    /// none on watchOS.
    @MainActor @usableFromInline static var defaults: [DebugDrawerSidecarPlugin] {
        #if canImport(DebugDrawerConsolePlugin) && canImport(DebugDrawerNetworkPlugin)
            [.console, .network]
        #else
            []
        #endif
    }

    #if canImport(DebugDrawerConsolePlugin)
        /// The Console plugin: the app's captured log lines, filtered and searched in the app.
        @MainActor public static var console: DebugDrawerSidecarPlugin {
            let console = ConsolePlugin()
            return DebugDrawerSidecarPlugin(
                id: console.id, title: console.title, icon: console.icon, snapshot: ConsoleSnapshot.self, command: ConsoleCommand.self
            ) { transport in
                ConsolePlugin(transport: transport)
            }
            .collectedWhileRunning()
        }
    #endif

    #if canImport(DebugDrawerNetworkPlugin)
        /// The Network plugin: the app's captured requests, with its mocks, conditions and ignored
        /// hosts.
        @MainActor public static var network: DebugDrawerSidecarPlugin {
            let network = NetworkPlugin()
            return DebugDrawerSidecarPlugin(
                id: network.id, title: network.title, icon: network.icon, snapshot: NetworkSnapshot.self, command: NetworkCommand.self
            ) { transport in
                NetworkPlugin(transport: transport)
            }
            .collectedWhileRunning()
        }
    #endif
}
