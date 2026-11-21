#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// One plugin of the app's: waiting for its model's first snapshot, then the plugin as the
    /// drawer shows it, or why it couldn't be reached. For an app that serves its capabilities
    /// only within a session (a production app's receiver), it says so in place of the plugin
    /// while no session is open, or while the open one's grant doesn't list it, rather than
    /// waiting on a snapshot that won't come or showing the last one the session served.
    struct SidecarPluginHost: View {
        /// Where the plugin is.
        enum Hosting {
            case waiting
            case shown(AnyDebugDrawerPlugin)
            case failed(DebugDrawerTransportError)
        }

        @ObservedObject var connection: DebugDrawerSidecarConnection
        let plugin: DebugDrawerSidecarPlugin
        @State private var hosting = Hosting.waiting

        var body: some View {
            Group {
                if connection.app.servesInSessionsOnly {
                    SidecarSessionReadingObserver(sessions: connection.sessions, plugin: plugin) {
                        hosted
                    }
                } else {
                    hosted
                }
            }
            // Cancelled as the plugin is no longer shown, which ends the wait. It goes on while the
            // session gate shows in its place, so the plugin appears as the session opens.
            .task {
                do throws(DebugDrawerTransportError) {
                    hosting = try await .shown(connection.host(plugin))
                } catch {
                    if error != .cancelled {
                        hosting = .failed(error)
                    }
                }
            }
        }

        @ViewBuilder private var hosted: some View {
            Group {
                switch hosting {
                case .waiting:
                    ProgressView("Waiting for \(plugin.title)…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                case let .shown(hosted):
                    SidecarHostedPlugin(plugin: hosted)
                        .environment(\.debugDrawerSidecarApp, connection.app)
                case let .failed(error):
                    DebugDrawerEmptyState("\(plugin.title) Not Reached", systemImage: "exclamationmark.triangle") {
                        Text(error.localizedDescription)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    /// What the open session lets a sidecar see of a plugin, for an app that serves its
    /// capabilities only within a session.
    enum SidecarSessionReading: Equatable {
        /// No session is open, or the app's sessions haven't been read yet.
        case noSession
        /// A session is open, but its grant doesn't list the plugin's model.
        case notGranted
        /// The session may read the plugin's model.
        case reading

        /// What `state`, the app's sessions as last read (`nil` before), lets a sidecar see of the
        /// model served under `pluginID`.
        init(state: DebugDrawerSessionState?, pluginID: String) {
            guard let session = state?.session else {
                self = .noSession
                return
            }
            self = session.grant.map { $0.capabilities.contains(pluginID) } ?? true ? .reading : .notGranted
        }
    }

    /// Follows the app's sessions, once read, and shows `content` only while they let the sidecar
    /// see `plugin`.
    private struct SidecarSessionReadingObserver<Content: View>: View {
        let sessions: DebugDrawerPluginTransport<DebugDrawerSessionState, DebugDrawerSessionCommand>?
        let plugin: DebugDrawerSidecarPlugin
        @ViewBuilder let content: () -> Content

        var body: some View {
            if let sessions {
                SidecarSessionTransportReading(sessions: sessions, plugin: plugin, content: content)
            } else {
                SidecarSessionGate(reading: .noSession, title: plugin.title, content: content)
            }
        }
    }

    private struct SidecarSessionTransportReading<Content: View>: View {
        @ObservedObject var sessions: DebugDrawerPluginTransport<DebugDrawerSessionState, DebugDrawerSessionCommand>
        let plugin: DebugDrawerSidecarPlugin
        @ViewBuilder let content: () -> Content

        var body: some View {
            SidecarSessionGate(reading: SidecarSessionReading(state: sessions.snapshot, pluginID: plugin.id), title: plugin.title, content: content)
        }
    }

    /// `content` while `reading` lets the sidecar see the plugin titled `title`, else why not.
    struct SidecarSessionGate<Content: View>: View {
        let reading: SidecarSessionReading
        let title: String
        @ViewBuilder let content: () -> Content

        var body: some View {
            switch reading {
            case .noSession:
                DebugDrawerEmptyState("No Session", systemImage: "lock") {
                    Text("Open a session to see \(title).")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .notGranted:
                DebugDrawerEmptyState("Not Granted", systemImage: "lock.slash") {
                    Text("This session's grant doesn't list \(title).")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .reading:
                content()
            }
        }
    }

    /// A plugin shown in the sidecar: its title and header accessory, as the drawer's header row
    /// draws them, over its body. Pushed from a row (the rows layout: an iPhone, the watch), the
    /// title is the screen's navigation title, and the header accessory scrolls with the body, as
    /// the drawer's watch list shows a plugin.
    struct SidecarHostedPlugin: View {
        let plugin: AnyDebugDrawerPlugin
        @Environment(\.sidecarPluginLayout) private var layout

        var body: some View {
            switch layout {
            case .picker: panel
            case .rows: pushed
            }
        }

        private var pushed: some View {
            ScrollView {
                VStack(alignment: .leading, spacing: 8) {
                    plugin.headerAccessory
                        .debugDrawerFont(.label)
                        .foregroundStyle(.secondary)
                    plugin.body
                }
                .debugDrawerFont(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                // The system's margins keep the rows off the screen's edges (on the watch, its
                // rounded corners).
                .scenePadding(.horizontal)
            }
        }

        private var panel: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Label(plugin.title, systemImage: plugin.icon)
                        .debugDrawerFont(.title)
                    Spacer()
                    plugin.headerAccessory
                        .debugDrawerFont(.label)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                ScrollView {
                    // Inset as the drawer's panel insets a plugin, at the header's margin: the
                    // shipped rows pad themselves only vertically.
                    VStack(alignment: .leading, spacing: 0) {
                        plugin.body
                    }
                    .debugDrawerFont(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 14)
                }
            }
        }
    }
#endif
