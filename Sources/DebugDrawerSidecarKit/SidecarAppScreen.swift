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
        #if os(iOS)
            @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        #endif

        /// Rows where the width is narrow (an iPhone, the watch), the picker where it isn't.
        private var layout: SidecarPluginLayout {
            #if os(iOS)
                SidecarPluginLayout(horizontalSizeClass: horizontalSizeClass)
            #else
                .platform
            #endif
        }

        var body: some View {
            Group {
                switch connection {
                case .connecting:
                    ProgressView("Connecting to \(app.displayName)…")
                case let .connected(connection):
                    SidecarConnectedScreen(
                        connection: connection, plugins: plugins.filter { app.serves($0.id) }, layout: layout,
                        sessionDuration: sessionDuration, grant: grant
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

    /// An app connected to, in the layout given. As a picker: its channel and session along the
    /// top, a picker of the plugins it serves (segments, or a menu where they don't fit) over the
    /// plugin picked, and the report along the bottom. As rows: a list of the same, the channel
    /// and session, a row per plugin that pushes it, and the report.
    struct SidecarConnectedScreen: View {
        @ObservedObject var connection: DebugDrawerSidecarConnection
        /// The plugins the app serves, in the sidecar's order.
        let plugins: [DebugDrawerSidecarPlugin]
        let layout: SidecarPluginLayout
        let sessionDuration: TimeInterval
        let grant: (@MainActor (DebugDrawerSidecarApp) async throws -> String)?
        @State private var selected: DebugDrawerSidecarPlugin.ID?
        #if canImport(DebugDrawerRemote)
            /// The device-lab relay's settings, when the sidecar app turned it on.
            @Environment(\.sidecarRelaySettings) private var relaySettings
        #endif

        var body: some View {
            Group {
                switch layout {
                case .picker: picker
                case .rows: rows
                }
            }
            .environment(\.sidecarPluginLayout, layout)
            // The app state goes in every report, so it is hosted as the app is reached, before
            // anyone picks it; cancelled with the screen.
            .task {
                await connection.hostOnConnect(plugins)
            }
        }

        /// Each plugin a row that pushes it, as the drawer's watch list shows plugins: on a narrow
        /// screen a segmented picker would cut the plugins' names short.
        private var rows: some View {
            List {
                Section {
                    SidecarStatusBar(app: connection.app, channel: connection.channel)
                    session
                    relay
                }
                Section("Plugins") {
                    if plugins.isEmpty {
                        noPlugins
                    }
                    ForEach(plugins) { plugin in
                        NavigationLink {
                            SidecarPluginHost(connection: connection, plugin: plugin)
                                .navigationTitle(plugin.title)
                                .environment(\.sidecarPluginLayout, layout)
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

        private var picker: some View {
            VStack(alignment: .leading, spacing: 0) {
                SidecarStatusBar(app: connection.app, channel: connection.channel)
                session
                relay
                Divider()
                if plugins.isEmpty {
                    noPlugins
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    if plugins.count > 1 {
                        SidecarPluginPicker(plugins: plugins, selection: shown)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                    }
                    if let plugin = plugins.first(where: { $0.id == shown.wrappedValue }) {
                        SidecarPluginHost(connection: connection, plugin: plugin)
                            .id(plugin.id)
                    }
                }
                Divider()
                SidecarReportBar(connection: connection)
            }
        }

        /// The plugin shown: the one picked, else the first, so the picker marks the plugin under it.
        private var shown: Binding<DebugDrawerSidecarPlugin.ID?> {
            Binding {
                selected.flatMap { id in plugins.first { $0.id == id }?.id } ?? plugins.first?.id
            } set: {
                selected = $0
            }
        }

        /// The app's session, for an app whose commands act only within one.
        @ViewBuilder private var session: some View {
            if connection.app.requiresSession {
                SidecarSessionControl(
                    sessions: connection.sessions,
                    open: openSession,
                    end: connection.endSession
                )
            }
        }

        /// The Mac Viewer control, when the sidecar app turned the relay on; nothing otherwise, so
        /// nothing listens.
        @ViewBuilder private var relay: some View {
            #if canImport(DebugDrawerRemote)
                if let relaySettings {
                    SidecarRelayHost(connection: connection, settings: relaySettings, layout: layout)
                }
            #endif
        }

        private var noPlugins: some View {
            DebugDrawerEmptyState("No Plugins", systemImage: "puzzlepiece.extension") {
                Text("\(connection.app.displayName) serves none of the plugins this sidecar shows.")
            }
        }

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
