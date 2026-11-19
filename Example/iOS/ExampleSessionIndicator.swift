import DebugDrawer
import ExampleTestBench
import SwiftUI

extension View {
    /// Serves a sidecar's sessions through the app group's store (the test bench's Sidecar Session
    /// actions play the sidecar; -RunTestBench sidecar.open opens one at launch), and shows
    /// ``ExampleSessionIndicator`` along the bottom, above the app's content, while one is open.
    func sidecarSessionIndicator() -> some View {
        ExampleSidecar.install()
        return safeAreaInset(edge: .bottom, spacing: 0) {
            ExampleSessionIndicator(sessions: ExampleSidecar.sessions, logLevel: ExampleSidecar.logLevel, keeper: ExampleSidecar.keeper)
        }
    }
}

/// The host's indicator for a sidecar session: a bar along the bottom of the screen for as long as
/// the receiver's published state is active, saying until when and what the session changed, with
/// an End button for the person holding the device, and what keeps the app running in the
/// background meanwhile. The library draws nothing: the host styles its own, as this one does. In
/// release the sessions never open, so it never shows.
struct ExampleSessionIndicator: View {
    @ObservedObject var sessions: DebugDrawerSessions
    @ObservedObject var logLevel: ExampleLogLevel
    @ObservedObject var keeper: DebugDrawerBackgroundKeeper

    var body: some View {
        if let session = sessions.snapshot.session {
            HStack(spacing: 12) {
                Image(systemName: "antenna.radiowaves.left.and.right")
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Debug session active")
                        .font(.headline)
                    Text("Ends at \(session.expires, style: .time) · Log level \(logLevel.snapshot.level)")
                        .font(.footnote)
                    Text("In the background: \(keeper.request.exampleDescription)")
                        .font(.footnote)
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("SidecarSessionIndicator")
                Spacer()
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
