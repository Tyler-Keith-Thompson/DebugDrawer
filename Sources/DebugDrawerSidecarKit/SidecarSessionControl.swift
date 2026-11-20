#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The app's session: reading it, none open with Open Session, or the one open, until when,
    /// with End Session. Why a session didn't open shows below it.
    struct SidecarSessionControl: View {
        /// The app's sessions, once read.
        let sessions: DebugDrawerPluginTransport<DebugDrawerSessionState, DebugDrawerSessionCommand>?
        /// Opens a session: why it couldn't, if it couldn't.
        let open: @MainActor () async -> String?
        let end: @MainActor () -> Void

        var body: some View {
            if let sessions {
                SidecarSessionRow(sessions: sessions, open: open, end: end)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityHidden(true)
                    Text("Reading the app's session…")
                        .debugDrawerFont(.secondary)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
        }
    }

    /// A session read from the app, drawn from its transport.
    struct SidecarSessionRow: View {
        @ObservedObject var sessions: DebugDrawerPluginTransport<DebugDrawerSessionState, DebugDrawerSessionCommand>
        let open: @MainActor () async -> String?
        let end: @MainActor () -> Void
        @State private var isOpening = false
        @State private var failure: String?

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    SidecarSessionStatus(state: sessions.snapshot)
                    Spacer()
                    if sessions.snapshot.isActive {
                        Button("End Session", action: end)
                            .debugDrawerButtonStyle(.destructive)
                    } else {
                        Button("Open Session") {
                            isOpening = true
                            failure = nil
                            Task {
                                failure = await open()
                                isOpening = false
                            }
                        }
                        .debugDrawerButtonStyle(.primary)
                        .disabled(isOpening)
                    }
                }
                if let failure {
                    DebugDrawerIssueRow("Session not opened", severity: .error) {
                        Text(failure)
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
        }
    }

    /// Whether a session is open, and until when.
    struct SidecarSessionStatus: View {
        let state: DebugDrawerSessionState

        var body: some View {
            if let session = state.session {
                Label {
                    Text("Session until \(session.expires, style: .time)")
                } icon: {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .accessibilityHidden(true)
                }
                .debugDrawerFont(.body)
            } else {
                Label {
                    Text("No session: the app refuses commands")
                } icon: {
                    Image(systemName: "lock")
                        .accessibilityHidden(true)
                }
                .debugDrawerFont(.body)
                .foregroundStyle(.secondary)
            }
        }
    }
#endif
