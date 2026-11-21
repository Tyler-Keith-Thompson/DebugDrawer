#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// Reads the server and hands its state to `RemoteViewingView`; every action runs on the
    /// server.
    struct RemoteViewingPluginView: View {
        @ObservedObject var server: DebugDrawerNetworkServer
        /// Whether a start this view asked for is waiting for the listener.
        @State private var isStarting = false
        /// Why the last start this view asked for failed, until the next one.
        @State private var startFailure: String?

        var body: some View {
            RemoteViewingView(
                state: state,
                requests: server.pairingRequests,
                viewers: server.pairedViewers,
                actions: RemoteViewingActions(
                    start: start,
                    stop: { server.stop() },
                    reject: { server.reject($0) },
                    disconnect: { server.disconnect($0) }
                )
            )
        }

        private var state: RemoteServingState {
            if let port = server.port {
                return .listening(port: port, loopbackOnly: server.configuration.loopbackOnly, advertises: server.configuration.advertises)
            }
            if isStarting { return .starting }
            if let startFailure { return .failed(startFailure) }
            return .stopped
        }

        private func start() {
            guard !isStarting else { return }
            isStarting = true
            startFailure = nil
            Task {
                do {
                    try await server.start()
                } catch {
                    startFailure = error.localizedDescription
                }
                isStarting = false
            }
        }
    }
#endif
