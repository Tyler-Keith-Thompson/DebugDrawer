#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The Remote Viewing plugin's face: the server's state with Start or Stop Serving, then,
    /// while it listens, the viewers asking to pair, each with its code and Reject, and the
    /// paired viewers, each with Disconnect.
    struct RemoteViewingView: View {
        let state: RemoteServingState
        let requests: [DebugDrawerPairingRequest]
        let viewers: [DebugDrawerPairedViewer]
        let actions: RemoteViewingActions

        var body: some View {
            serverSection
            // A stopped server holds no request or viewer; one that failed to start never had any.
            if case .listening = state {
                RemotePairingRequestsSection(requests: requests, reject: actions.reject)
                RemotePairedViewersSection(viewers: viewers, disconnect: actions.disconnect)
            }
        }

        private var serverSection: some View {
            DebugDrawerSection("Server") {
                DebugDrawerKeyValueRow("Status", value: status)
                if case let .listening(port, loopbackOnly, advertises) = state {
                    DebugDrawerKeyValueRow("Port", value: String(port))
                    DebugDrawerKeyValueRow("Address", value: loopbackOnly ? "127.0.0.1 only" : "Every interface")
                    DebugDrawerKeyValueRow("Bonjour", value: advertises ? "Advertised" : "Not advertised")
                }
                if case let .failed(reason) = state {
                    DebugDrawerIssueRow("Couldn't start serving", severity: .error) {
                        Text(reason)
                    }
                }
                DebugDrawerActionRow {
                    if case .listening = state {
                        Button("Stop Serving", action: actions.stop)
                            .accessibilityLabel("Stop serving remote viewers")
                            .help("Stop listening and disconnect every viewer")
                    } else {
                        Button("Start Serving", action: actions.start)
                            .debugDrawerButtonStyle(.primary)
                            .disabled(state == .starting)
                            .accessibilityLabel("Start serving remote viewers")
                            .help("Listen for viewers on other devices")
                    }
                }
            } footer: {
                if !isListening {
                    Text("Nothing listens until you start serving. A viewer on another device then pairs with a code shown here.")
                }
            }
        }

        private var isListening: Bool {
            if case .listening = state { return true }
            return false
        }

        private var status: String {
            switch state {
            case .stopped, .failed: "Not listening"
            case .starting: "Starting…"
            case .listening: "Listening"
            }
        }
    }
#endif
