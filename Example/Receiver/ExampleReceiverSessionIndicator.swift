import DebugDrawerLocation
import DebugDrawerReceiver
import SwiftUI

/// The host's indicator for a sidecar session: a bar along the bottom for as long as one is open,
/// saying who holds its grant, until when, which backend a switch points the app at, where a spoof
/// puts the app's location, and what keeps the app running meanwhile, with End Session for the
/// person holding the device and Keep Running for before they switch to the sidecar. The library
/// draws no indicator: the host styles its own.
struct ExampleReceiverSessionIndicator: View {
    @ObservedObject var sessions: DebugDrawerSessions
    @ObservedObject var keeper: DebugDrawerBackgroundKeeper
    @ObservedObject var environments: DebugDrawerEnvironments
    @ObservedObject var spoofing: LocationSpoofing
    let keepRunning: () -> Void

    var body: some View {
        // A switched environment and a spoofed location last only for the session, so the bar is up
        // for as long as they are.
        if let session = sessions.snapshot.session {
            HStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Debug session active")
                        .font(.headline)
                    Text("\(session.grant?.subject ?? "No grant") · ends at \(session.expires, style: .time)")
                        .font(.footnote)
                    if environments.snapshot.isSwitched {
                        Label("Backend: \(environments.snapshot.activeTitle)", systemImage: "server.rack")
                            .font(.footnote.bold())
                            .accessibilityIdentifier("SidecarSessionEnvironment")
                    }
                    if let coordinate = spoofing.snapshot.coordinate {
                        Label(
                            "Location spoofed: \(String(format: "%.4f, %.4f", coordinate.latitude, coordinate.longitude))",
                            systemImage: "location.slash"
                        )
                        .font(.footnote.bold())
                        .accessibilityIdentifier("SidecarSessionLocation")
                    }
                    Text("In the background: \(keeper.request.exampleDescription)")
                        .font(.footnote)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("SidecarSessionIndicator")
                Spacer()
                #if os(iOS)
                    // Only iOS suspends a backgrounded app; the Mac's keeper already holds off App Nap.
                    if keeper.request != .continuedProcessing {
                        Button("Keep Running", action: keepRunning)
                            .buttonStyle(.bordered)
                            .accessibilityHint("Asks the system to keep the app running while you use the sidecar")
                    }
                #endif
                Button("End Session") { sessions.end() }
                    .buttonStyle(.borderedProminent)
                    .tint(.black.opacity(0.25))
            }
            .foregroundStyle(.white)
            .padding(.horizontal)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(.orange)
        }
    }
}

extension DebugDrawerBackgroundRequest {
    /// What the indicator says keeps the app running.
    fileprivate var exampleDescription: String {
        switch self {
        case .none: "not kept running"
        case .backgroundTask: "background task"
        case .continuedProcessing: "continued processing"
        case .activity: "App Nap held off"
        }
    }
}
