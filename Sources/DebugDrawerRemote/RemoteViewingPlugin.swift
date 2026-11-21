import DebugDrawer
import SwiftUI

// The public API compiles in every configuration; the implementation under `#if DEBUG` below does
// not, so release builds get an empty view and hooks that do nothing.
//
// It lives beside the server it shows rather than in a plugin module of its own, which would
// depend on this one, where a plugin depends only on core and Apple frameworks. Start and Stop
// Serving are in it too: starting is the person holding the device deciding to let a viewer in
// (on iOS it raises the local network prompt), and the drawer is where they are. Rejected: leaving
// Start and Stop to the host, which every host would write again, beside a plugin that shows a
// server that may never start.

/// A ``/DebugDrawerRemote/DebugDrawerNetworkServer`` in the drawer: whether it listens and on which
/// port, with Start and Stop Serving, each viewer asking to pair with its name and code and a
/// Reject button, and each paired viewer with a Disconnect button. A badge counts the viewers
/// waiting for their code.
///
/// ```swift
/// DebugDrawer.shared.registerGlobal(RemoteViewingPlugin(server: server))
/// ```
///
/// Release builds list nothing: the plugin draws nothing and its server never listens.
public struct RemoteViewingPlugin: DebugDrawerPlugin {
    /// The plugin's identity in the drawer, which its badge is set under.
    nonisolated static let pluginID = "RemoteViewingPlugin"

    public nonisolated var id: String {
        Self.pluginID
    }

    public var title = "Remote Viewing"
    public var category = "Logs & Network"
    public var icon = "laptopcomputer.and.iphone"

    /// The server the plugin shows and drives.
    let server: DebugDrawerNetworkServer

    /// A plugin showing `server`, which it starts only when the person taps Start Serving.
    ///
    /// - Parameter server: The app's server.
    public init(server: DebugDrawerNetworkServer) {
        self.server = server
    }

    public var body: some View {
        #if DEBUG
            RemoteViewingPluginView(server: server)
        #else
            EmptyView()
        #endif
    }

    /// Shows the number of viewers waiting for their code as the plugin's badge in `drawer`, and
    /// keeps it up to date there. Release builds show nothing.
    @MainActor public func install(in drawer: DebugDrawer) {
        #if DEBUG
            server.badge.show(server.pairingRequests.count, in: drawer)
        #endif
    }

    /// Clears the badge from `drawer`. The server keeps serving: stopping it is the app's call,
    /// or the person's, through Stop Serving.
    @MainActor public func uninstall(from drawer: DebugDrawer) {
        #if DEBUG
            server.badge.remove(from: drawer)
        #endif
    }
}
