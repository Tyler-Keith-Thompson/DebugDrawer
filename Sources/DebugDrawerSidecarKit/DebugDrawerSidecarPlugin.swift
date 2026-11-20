import DebugDrawer
import DebugDrawerConsolePlugin
import DebugDrawerNetworkPlugin
import SwiftUI

// A plugin the sidecar can show: the ID its model is served under in the app, and how to make the
// plugin over a transport to that model. The plugin is a `DebugDrawerPlugin` like any other, so the
// kit draws its body and header accessory as the drawer would, and puts it in the bug report through
// `DebugDrawerReportContributor`, without knowing its types. Console and Network ship here, as
// they are the plugins every sidecar wants; any other plugin whose model adopts
// `DebugDrawerPluginModel` comes in through the generic initializer, from a module the host links.
//
// Rejected: a protocol in core that plugins adopt to be hosted (a plugin's model ID is only known
// from an instance, and core would grow a second plugin contract for one caller); the kit depending
// on every plugin with a model (a sidecar would link them all, the N5 shape); and the host writing
// a view per plugin (the plugins' own views over a transport already exist).

/// A plugin a sidecar shows for an app, drawn from the app's model of it over the sidecar's
/// transport.
///
/// ```swift
/// DebugDrawerSidecarView(groupIdentifier: "TEAMID.com.example.debug", plugins: [.console, .network])
/// ```
///
/// ``console`` and ``network`` show the Console and Network plugins. Any plugin whose model the app
/// serves comes in through ``init(id:title:icon:snapshot:command:plugin:)``, with the plugin made
/// over the transport.
public struct DebugDrawerSidecarPlugin: Identifiable {
    /// The ID the app serves the plugin's model under.
    public let id: String
    /// The plugin's name, as the sidecar lists it.
    public let title: String
    /// The plugin's SF Symbol name.
    public let icon: String
    /// Connects to the model over a transport and makes the plugin over it.
    let connect: @MainActor (any DebugDrawerTransport) async throws(DebugDrawerTransportError) -> AnyDebugDrawerPlugin
    /// Whether the sidecar view hosts it as soon as the app is reached rather than when it is
    /// picked, so its report contribution is in every report: the app state's.
    var hostsOnConnect = false

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
        connect = { transport throws(DebugDrawerTransportError) in
            let connected = try await transport.connect(toPlugin: id, snapshot: snapshot, command: command)
            return AnyDebugDrawerPlugin(plugin(connected))
        }
    }

    /// The Console plugin: the app's captured log lines, filtered and searched in the app.
    @MainActor public static var console: DebugDrawerSidecarPlugin {
        let console = ConsolePlugin()
        return DebugDrawerSidecarPlugin(
            id: console.id, title: console.title, icon: console.icon, snapshot: ConsoleSnapshot.self, command: ConsoleCommand.self
        ) { transport in
            ConsolePlugin(transport: transport)
        }
    }

    /// The Network plugin: the app's captured requests, with its mocks, conditions and ignored
    /// hosts.
    @MainActor public static var network: DebugDrawerSidecarPlugin {
        let network = NetworkPlugin()
        return DebugDrawerSidecarPlugin(
            id: network.id, title: network.title, icon: network.icon, snapshot: NetworkSnapshot.self, command: NetworkCommand.self
        ) { transport in
            NetworkPlugin(transport: transport)
        }
    }
}
