import DebugDrawer
import DebugDrawerRemote
import Foundation

// The example's device side of remote viewing: a network server over the models the app offers
// (its Console and Network), started only when asked (the shipped Remote Viewing plugin's Start
// Serving button, or the launch argument), and that plugin in the drawer to show each viewer's
// pairing code. The macOS example's Remote window is the viewer; it can view this app too, on the
// same Mac. Everything compiles in release, where the server never listens and the plugin draws
// nothing.

/// The example's remote viewing server, shown in the drawer by `RemoteViewingPlugin`.
@MainActor
public enum ExampleRemoteServer {
    /// Launched with this argument, the app starts serving at launch.
    public nonisolated static let launchArgument = "-ServeRemoteViewers"
    /// Launched with this one too, it listens on 127.0.0.1 alone and advertises nothing, so a
    /// viewer on the same Mac connects by address and no local network permission is asked for.
    public nonisolated static let loopbackArgument = "-RemoteViewersOnLoopback"
    private static let registry = DebugDrawerModelRegistry()
    /// The server; it listens only once started.
    public static let server = DebugDrawerNetworkServer(
        registry: registry,
        configuration: ProcessInfo.processInfo.arguments.contains(loopbackArgument) ? .loopback : .init()
    )
    private static var isInstalled = false

    /// Offers `model` to paired viewers under `id`.
    public static func offer<Model: DebugDrawerPluginModel>(_ model: Model, id: String) {
        registry.register(model, id: id)
    }

    /// Lists the Remote Viewing plugin in the drawer, and starts serving when the app was launched
    /// with ``launchArgument``. Later calls do nothing.
    public static func install() {
        guard !isInstalled else { return }
        isInstalled = true
        DebugDrawer.shared.registerGlobal(RemoteViewingPlugin(server: server))
        if ProcessInfo.processInfo.arguments.contains(launchArgument) {
            start()
        }
    }

    /// Starts listening, and advertising unless on loopback, for the launch argument; logs why it
    /// couldn't. The plugin's Start Serving shows its own failure.
    private static func start() {
        Task {
            do {
                try await server.start()
                print("[Remote] Serving on port \(server.port.map(String.init) ?? "none")")
            } catch {
                print("[Remote] The server didn't start: \(error)")
            }
        }
    }
}
