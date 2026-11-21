#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The detail for one app: its connection, once made, or why it couldn't be.
    struct SidecarAppScreen: View {
        /// Where the connection to the app is.
        enum Connection {
            case connecting
            case connected(DebugDrawerSidecarConnection)
            case failed(DebugDrawerTransportError)
        }

        let app: DebugDrawerSidecarApp
        let plugins: [DebugDrawerSidecarPlugin]
        let sessionDuration: TimeInterval
        let grant: (@MainActor (DebugDrawerSidecarApp) async throws -> String)?
        @State private var connection = Connection.connecting

        var body: some View {
            Group {
                switch connection {
                case .connecting:
                    ProgressView("Connecting to \(app.displayName)…")
                case let .connected(connection):
                    SidecarConnectedScreen(
                        connection: connection, plugins: plugins.filter { app.serves($0.id) }, sessionDuration: sessionDuration, grant: grant
                    )
                case let .failed(error):
                    DebugDrawerEmptyState("Not Connected", systemImage: "bolt.horizontal.circle") {
                        Text(error.localizedDescription)
                    }
                }
            }
            .navigationTitle(app.displayName)
            // Once per screen: the connection, and the transports it holds, go with the screen's
            // state when another app is picked.
            .onAppear {
                guard case .connecting = connection else { return }
                do throws(DebugDrawerTransportError) {
                    connection = try .connected(DebugDrawerSidecarConnection(app: app))
                } catch {
                    connection = .failed(error)
                }
            }
        }
    }

    /// An app connected to: its channel and session along the top, a picker of the plugins it
    /// serves, the plugin picked, and the report. On watchOS, a list of the same: the channel and
    /// session, a row per plugin that pushes it, and the report.
    struct SidecarConnectedScreen: View {
        @ObservedObject var connection: DebugDrawerSidecarConnection
        /// The plugins the app serves, in the sidecar's order.
        let plugins: [DebugDrawerSidecarPlugin]
        let sessionDuration: TimeInterval
        let grant: (@MainActor (DebugDrawerSidecarApp) async throws -> String)?
        @State private var selected: DebugDrawerSidecarPlugin.ID?

        var body: some View {
            content
                // The app state goes in every report, so it is hosted as the app is reached, before
                // anyone picks it; cancelled with the screen.
                .task {
                    await connection.hostOnConnect(plugins)
                }
        }

        #if os(watchOS)
            // A watch has no room for a picker over the plugin's view, so each plugin is a row that
            // pushes it, as the drawer's watch list does.
            private var content: some View {
                List {
                    Section {
                        SidecarStatusBar(app: connection.app, channel: connection.channel)
                        if connection.app.requiresSession {
                            SidecarSessionControl(
                                sessions: connection.sessions,
                                open: openSession,
                                end: connection.endSession
                            )
                        }
                    }
                    Section("Plugins") {
                        if plugins.isEmpty {
                            DebugDrawerEmptyState("No Plugins", systemImage: "puzzlepiece.extension") {
                                Text("\(connection.app.displayName) serves none of the plugins this sidecar shows.")
                            }
                        }
                        ForEach(plugins) { plugin in
                            NavigationLink {
                                SidecarPluginHost(connection: connection, plugin: plugin)
                                    .navigationTitle(plugin.title)
                            } label: {
                                Label(plugin.title, systemImage: plugin.icon)
                            }
                        }
                    }
                    Section {
                        SidecarReportBar(connection: connection)
                    }
                }
            }
        #else
            private var content: some View {
                VStack(alignment: .leading, spacing: 0) {
                    SidecarStatusBar(app: connection.app, channel: connection.channel)
                    if connection.app.requiresSession {
                        SidecarSessionControl(
                            sessions: connection.sessions,
                            open: openSession,
                            end: connection.endSession
                        )
                    }
                    Divider()
                    if plugins.isEmpty {
                        DebugDrawerEmptyState("No Plugins", systemImage: "puzzlepiece.extension") {
                            Text("\(connection.app.displayName) serves none of the plugins this sidecar shows.")
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        if plugins.count > 1 {
                            Picker("Plugin", selection: $selected) {
                                ForEach(plugins) { plugin in
                                    Label(plugin.title, systemImage: plugin.icon).tag(Optional(plugin.id))
                                }
                            }
                            .pickerStyle(.segmented)
                            .labelsHidden()
                            .accessibilityElement(children: .contain)
                            .accessibilityLabel("Plugin")
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                        }
                        if let plugin = plugins.first(where: { $0.id == selected }) ?? plugins.first {
                            SidecarPluginHost(connection: connection, plugin: plugin)
                                .id(plugin.id)
                        }
                    }
                    Divider()
                    SidecarReportBar(connection: connection)
                }
            }
        #endif

        /// Opens a session, with a grant first when the sidecar fetches them: the error that
        /// stopped it, if one did.
        private func openSession() async -> String? {
            do {
                let token = try await grant?(connection.app)
                connection.openSession(duration: sessionDuration, grant: token)
                return nil
            } catch {
                return error.localizedDescription
            }
        }
    }

    /// The app's version and how the sidecar reaches it now.
    struct SidecarStatusBar: View {
        let app: DebugDrawerSidecarApp
        let channel: DebugDrawerSidecarTransport.Channel

        var body: some View {
            HStack(spacing: 8) {
                Text(app.versionLine)
                    .debugDrawerFont(.value)
                    .foregroundStyle(.secondary)
                Spacer()
                Label(channel.title, systemImage: channel.systemImage)
                    .debugDrawerFont(.label)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Connected over \(channel.title)")
            }
            .sidecarBarPadding()
        }
    }

    extension DebugDrawerSidecarTransport.Channel {
        /// The channel's name in the status bar.
        var title: String {
            switch self {
            case .socket: "Socket"
            case .store: "Store"
            }
        }

        fileprivate var systemImage: String {
            switch self {
            case .socket: "bolt.horizontal"
            case .store: "tray.full"
            }
        }
    }
#endif
