#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// One plugin of the app's: waiting for its model's first snapshot, then the plugin as the
    /// drawer shows it, or why it couldn't be reached. For an app that serves its capabilities
    /// only within a session (a production app's receiver), it says so in place of the plugin
    /// while no session is open, or while the open one's grant doesn't list it, rather than
    /// waiting on a snapshot that won't come or showing the last one the session served. While a
    /// session's open waits for the app to launch, it shows the plugin prepared from what the
    /// sidecar last read of it, or that it can't be prepared.
    struct SidecarPluginHost: View {
        /// Where the plugin is.
        enum Hosting {
            case waiting
            case shown(AnyDebugDrawerPlugin)
            /// The app isn't serving it yet and the sidecar never read it, so there's nothing to
            /// prepare before launch.
            case notPrepared
            case failed(DebugDrawerTransportError)
        }

        @ObservedObject var connection: DebugDrawerSidecarConnection
        let plugin: DebugDrawerSidecarPlugin
        @State private var hosting = Hosting.waiting

        var body: some View {
            Group {
                if connection.app.servesInSessionsOnly {
                    SidecarSessionReadingObserver(
                        sessions: connection.sessions, plugin: plugin, isWaitingForLaunch: connection.isWaitingForLaunch
                    ) {
                        hosted
                    }
                } else {
                    hosted
                }
            }
            // Cancelled as the plugin is no longer shown, which ends the wait. It goes on while the
            // session gate shows in its place, so the plugin appears as the session opens. Run
            // again as an open starts or stops waiting for the app's launch: while it waits, the
            // plugin is prepared from what was read before.
            .task(id: connection.isWaitingForLaunch) {
                if connection.isWaitingForLaunch {
                    do throws(DebugDrawerSidecarConnection.NeverRead) {
                        hosting = try .shown(connection.prepare(plugin))
                    } catch {
                        hosting = .notPrepared
                    }
                }
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
                    VStack(alignment: .leading, spacing: 0) {
                        if connection.preparedForLaunch.contains(plugin.id) {
                            SidecarPreparedForLaunchNote(app: connection.app, isWaitingForLaunch: connection.isWaitingForLaunch)
                        }
                        SidecarHostedPlugin(plugin: hosted)
                            .environment(\.debugDrawerSidecarApp, connection.app)
                    }
                case .notPrepared:
                    DebugDrawerEmptyState("Can't Be Prepared", systemImage: "clock.badge.questionmark") {
                        Text(
                            """
                            The sidecar hasn't read \(plugin.title) from \(connection.app.displayName) yet, so it can't be \
                            prepared before launch. It shows here once the app serves it.
                            """
                        )
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case let .failed(error):
                    DebugDrawerEmptyState("\(plugin.title) Not Reached", systemImage: "exclamationmark.triangle") {
                        Text(error.localizedDescription)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
    }

    /// A note over a plugin prepared before the app launches: what is shown is what the sidecar
    /// last read, and what is sent waits for the launch.
    struct SidecarPreparedForLaunchNote: View {
        let app: DebugDrawerSidecarApp
        let isWaitingForLaunch: Bool

        var body: some View {
            DebugDrawerIssueRow("Prepared for launch", severity: .warning) {
                if isWaitingForLaunch {
                    Text("Shown as \(app.displayName) was last read. What you change waits, and applies in the session as the app starts.")
                } else {
                    Text("Shown as \(app.displayName) was last read, until the app serves it again.")
                }
            }
            .sidecarBarPadding()
        }
    }

    /// What the open session lets a sidecar see of a plugin, for an app that serves its
    /// capabilities only within a session.
    enum SidecarSessionReading: Equatable {
        /// No session is open, or the app's sessions haven't been read yet.
        case noSession
        /// No session is open yet, but one's open waits for the app to launch: the plugin can be
        /// prepared for it.
        case waitingForLaunch
        /// A session is open, but its grant doesn't list the plugin's model.
        case notGranted
        /// The session may read the plugin's model.
        case reading

        /// What `state`, the app's sessions as last read (`nil` before), lets a sidecar see of the
        /// model served under `pluginID`, while an open waits for the app's launch, or not.
        init(state: DebugDrawerSessionState?, pluginID: String, isWaitingForLaunch: Bool = false) {
            guard let session = state?.session else {
                self = isWaitingForLaunch ? .waitingForLaunch : .noSession
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
        let isWaitingForLaunch: Bool
        @ViewBuilder let content: () -> Content

        var body: some View {
            if let sessions {
                SidecarSessionTransportReading(sessions: sessions, plugin: plugin, isWaitingForLaunch: isWaitingForLaunch, content: content)
            } else {
                SidecarSessionGate(
                    reading: SidecarSessionReading(state: nil, pluginID: plugin.id, isWaitingForLaunch: isWaitingForLaunch),
                    title: plugin.title, content: content
                )
            }
        }
    }

    private struct SidecarSessionTransportReading<Content: View>: View {
        @ObservedObject var sessions: DebugDrawerPluginTransport<DebugDrawerSessionState, DebugDrawerSessionCommand>
        let plugin: DebugDrawerSidecarPlugin
        let isWaitingForLaunch: Bool
        @ViewBuilder let content: () -> Content

        var body: some View {
            SidecarSessionGate(
                reading: SidecarSessionReading(state: sessions.snapshot, pluginID: plugin.id, isWaitingForLaunch: isWaitingForLaunch),
                title: plugin.title, content: content
            )
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
            case .waitingForLaunch, .reading:
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
