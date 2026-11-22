#if DEBUG && canImport(DebugDrawerRemote)
    import DebugDrawer
    import DebugDrawerRemote
    import SwiftUI

    // The Mac Viewer control on an app's screen, when the sidecar app turned the relay on: the
    // relay for the app, made with the screen and gone with it (its server stops then), shown as a
    // bar above the plugins with what it shares, and the Remote Viewing plugin's own view for the
    // server (Start and Stop Serving, each viewer's code with Reject, each paired viewer with
    // Disconnect), in a popover there or pushed from a row in the rows layout. Rejected: a view of
    // the codes of its own (the Remote Viewing plugin's already shows them, and reads them aloud
    // digit by digit).

    /// The app's relay, as the layout shows it: a bar that shows it below, or a row that pushes it.
    struct SidecarRelayHost: View {
        @StateObject private var relay: DebugDrawerSidecarRelay
        let layout: SidecarPluginLayout
        let startsServing: Bool
        @State private var isShowingViewers = false

        init(connection: DebugDrawerSidecarConnection, settings: SidecarRelaySettings, layout: SidecarPluginLayout) {
            _relay = StateObject(wrappedValue: DebugDrawerSidecarRelay(connection: connection, configuration: settings.configuration))
            self.layout = layout
            startsServing = settings.startsServing
        }

        var body: some View {
            Group {
                switch layout {
                case .picker:
                    VStack(alignment: .leading, spacing: 0) {
                        SidecarRelayBar(relay: relay, server: relay.server, isShowingViewers: $isShowingViewers)
                        if isShowingViewers {
                            SidecarRelayDetail(relay: relay)
                                .padding(.horizontal, 14)
                                .padding(.bottom, 8)
                        }
                    }
                case .rows:
                    NavigationLink {
                        List {
                            SidecarRelayDetail(relay: relay)
                        }
                        .navigationTitle("Mac Viewer")
                    } label: {
                        SidecarRelayStatus(relay: relay, server: relay.server)
                    }
                }
            }
            .task {
                guard startsServing else { return }
                // A failure shows in the Remote Viewing view's Start Serving, tried again there.
                try? await relay.start()
            }
        }
    }

    /// What the relay shares now, and the button that shows or hides its viewers below it.
    struct SidecarRelayBar: View {
        @ObservedObject var relay: DebugDrawerSidecarRelay
        @ObservedObject var server: DebugDrawerNetworkServer
        @Binding var isShowingViewers: Bool

        var body: some View {
            HStack(spacing: 8) {
                SidecarRelayStatus(relay: relay, server: server)
                Spacer()
                Button(isShowingViewers ? "Hide Mac Viewer" : "Show Mac Viewer") { isShowingViewers.toggle() }
                    .debugDrawerButtonStyle(server.pairingRequests.isEmpty || isShowingViewers ? .secondary : .primary)
                    .accessibilityLabel(isShowingViewers ? "Hide Mac Viewer" : "Show Mac Viewer")
                    .accessibilityHint("The pairing codes and the Macs viewing this app")
            }
            .sidecarBarPadding()
        }
    }

    /// The relay's state in a line, from the server's and the relay's own.
    struct SidecarRelayStatus: View {
        @ObservedObject var relay: DebugDrawerSidecarRelay
        @ObservedObject var server: DebugDrawerNetworkServer

        var body: some View {
            SidecarRelayStatusLine(
                isServing: server.isRunning,
                waiting: server.pairingRequests.count,
                paired: server.pairedViewers.count,
                snapshot: relay.snapshot
            )
        }
    }

    /// The relay's state in a line: a function of the server's counts and the relay's snapshot.
    struct SidecarRelayStatusLine: View {
        let isServing: Bool
        let waiting: Int
        let paired: Int
        let snapshot: DebugDrawerSidecarRelay.Snapshot

        var body: some View {
            Label {
                Text(text)
            } icon: {
                Image(systemName: "laptopcomputer.and.iphone")
                    .accessibilityHidden(true)
            }
            .debugDrawerFont(.body)
            .foregroundStyle(isServing ? .primary : .secondary)
        }

        private var text: String {
            guard isServing else { return "Mac Viewer: not sharing" }
            var parts: [String] = []
            if waiting > 0 { parts.append("\(waiting) waiting for a code") }
            parts.append(paired == 1 ? "1 Mac paired" : "\(paired) Macs paired")
            parts.append(snapshot.isRelaying ? "sharing \(snapshot.pluginIDs.count) plugins in this session" : "nothing shared until a session opens")
            return "Mac Viewer: " + parts.joined(separator: ", ")
        }
    }

    /// The relay in full: what it shares, then the Remote Viewing plugin's view of its server.
    struct SidecarRelayDetail: View {
        @ObservedObject var relay: DebugDrawerSidecarRelay

        var body: some View {
            DebugDrawerSection("Shared with a Mac") {
                if let expires = relay.snapshot.sessionExpires {
                    DebugDrawerKeyValueRow("Until", value: expires.formatted(date: .omitted, time: .shortened))
                    let shared = relay.snapshot.pluginIDs
                    DebugDrawerKeyValueRow("Plugins", value: shared.isEmpty ? "None yet" : shared.joined(separator: ", "))
                } else {
                    DebugDrawerKeyValueRow("Plugins", value: "None: no session is open")
                }
            } footer: {
                Text("A paired Mac reads and drives what this session may, until it ends. Traffic isn't encrypted: share on a network you trust.")
            }
            RemoteViewingPlugin(server: relay.server).body
        }
    }
#endif
