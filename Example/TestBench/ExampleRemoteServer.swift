import DebugDrawer
import DebugDrawerRemote
import Foundation
import SwiftUI

// The example's device side of remote viewing: a network server over the models the app offers
// (its Console and Network), started only when asked (the Remote Viewing plugin's Start button, or
// the launch argument), and the plugin that shows each viewer's pairing code. The macOS example's
// Remote window is the viewer; it can view this app too, on the same Mac. Everything compiles in
// release, where the server never listens and the plugin isn't listed.

/// The example's remote viewing server and the drawer plugin that shows its pairing codes.
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
        DebugDrawer.shared.registerGlobal(ExampleRemotePairingPlugin(server: server))
        if ProcessInfo.processInfo.arguments.contains(launchArgument) {
            start()
        }
    }

    /// Starts listening, and advertising unless on loopback; logs why it couldn't.
    static func start() {
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

/// Serving or not, the code for each viewer asking to pair, with Reject, and the paired viewers,
/// with Disconnect.
struct ExampleRemotePairingPlugin: DebugDrawerPlugin {
    let server: DebugDrawerNetworkServer
    var title = "Remote Viewing"
    var icon = "laptopcomputer.and.iphone"
    var category = "Logs & Network"

    var body: some View {
        ExampleRemotePairingList(server: server)
    }
}

struct ExampleRemotePairingList: View {
    @ObservedObject var server: DebugDrawerNetworkServer

    var body: some View {
        DebugDrawerSection("Server") {
            DebugDrawerKeyValueRow("Status", value: status)
            if server.isRunning {
                Button("Stop Serving") { server.stop() }
                    .debugDrawerButtonStyle(.secondary)
            } else {
                Button("Start Serving") { ExampleRemoteServer.start() }
                    .debugDrawerButtonStyle(.secondary)
            }
        }
        if !server.pairingRequests.isEmpty {
            DebugDrawerSection("Pairing Codes") {
                ForEach(server.pairingRequests) { request in
                    DebugDrawerKeyValueRow(request.viewerName, value: request.code)
                    Button("Reject \(request.viewerName)") { server.reject(request) }
                        .debugDrawerButtonStyle(.secondary)
                }
            }
        }
        if !server.pairedViewers.isEmpty {
            DebugDrawerSection("Paired Viewers") {
                ForEach(server.pairedViewers) { viewer in
                    Button("Disconnect \(viewer.name)") { server.disconnect(viewer) }
                        .debugDrawerButtonStyle(.secondary)
                }
            }
        }
    }

    private var status: String {
        guard server.isRunning, let port = server.port else { return "Not serving" }
        let scope = server.configuration.loopbackOnly ? "127.0.0.1" : "the local network"
        return "Port \(port) on \(scope)"
    }
}
