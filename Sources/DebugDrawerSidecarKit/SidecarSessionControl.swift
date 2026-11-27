#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The app's session: reading it, none open with Open Session, the one open, until when,
    /// with End Session, or one waiting for the app to launch. Why a session didn't open shows
    /// below it. While the sessions aren't read, as for an app that never launched, Open Session
    /// still leaves the open for the app.
    struct SidecarSessionControl: View {
        /// The app's sessions, once read.
        let sessions: DebugDrawerPluginTransport<DebugDrawerSessionState, DebugDrawerSessionCommand>?
        /// Whether an open waits in the store for the app to launch.
        let isWaitingForLaunch: Bool
        /// The app's name, for the wait.
        let appName: String
        /// Opens a session: why it couldn't, if it couldn't.
        let open: @MainActor () async -> String?
        let end: @MainActor () -> Void

        var body: some View {
            if isWaitingForLaunch {
                SidecarWaitingForLaunchRow(appName: appName)
            } else if let sessions {
                SidecarSessionRow(sessions: sessions, open: open, end: end)
            } else {
                SidecarUnreadSessionRow(open: open)
            }
        }
    }

    /// An open left for the app, which it hasn't taken yet.
    struct SidecarWaitingForLaunchRow: View {
        let appName: String

        var body: some View {
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityHidden(true)
                Text("Waiting for launch: the session opens as \(appName) starts")
                    .debugDrawerFont(.secondary)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)
            .sidecarBarPadding()
        }
    }

    /// Sessions not read yet: the app hasn't served them, perhaps never launched. Open Session
    /// leaves the open for its launch.
    struct SidecarUnreadSessionRow: View {
        let open: @MainActor () async -> String?
        @State private var failure: String?

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("The app's session hasn't been read")
                        .debugDrawerFont(.secondary)
                        .foregroundStyle(.secondary)
                    Spacer()
                    SidecarOpenSessionButton(open: open, failure: $failure)
                }
                if let failure {
                    DebugDrawerIssueRow("Session not opened", severity: .error) {
                        Text(failure)
                    }
                }
            }
            .sidecarBarPadding()
        }
    }

    /// A session read from the app, drawn from its transport.
    struct SidecarSessionRow: View {
        @ObservedObject var sessions: DebugDrawerPluginTransport<DebugDrawerSessionState, DebugDrawerSessionCommand>
        let open: @MainActor () async -> String?
        let end: @MainActor () -> Void
        @State private var failure: String?

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                #if os(watchOS)
                    // The status and its button don't fit one watch row: the button goes below,
                    // the row's width.
                    SidecarSessionStatus(state: sessions.snapshot)
                    button
                #else
                    HStack(spacing: 8) {
                        SidecarSessionStatus(state: sessions.snapshot)
                        Spacer()
                        button
                    }
                #endif
                if let failure {
                    DebugDrawerIssueRow("Session not opened", severity: .error) {
                        Text(failure)
                    }
                }
            }
            .sidecarBarPadding()
        }

        /// End Session while one is open, else Open Session.
        @ViewBuilder private var button: some View {
            if sessions.snapshot.isActive {
                Button("End Session", action: end)
                    .debugDrawerButtonStyle(.destructive)
            } else {
                SidecarOpenSessionButton(open: open, failure: $failure)
            }
        }
    }

    /// Open Session: disabled while it opens, and why it didn't, if it didn't, in `failure`.
    struct SidecarOpenSessionButton: View {
        let open: @MainActor () async -> String?
        @Binding var failure: String?
        @State private var isOpening = false

        var body: some View {
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

    extension View {
        /// The margins of a row along the top or bottom of an app's screen, at the plugin header's
        /// inset; none in the rows layout, whose list insets its rows itself.
        func sidecarBarPadding() -> some View {
            modifier(SidecarBarPadding())
        }
    }

    /// The margins `sidecarBarPadding()` gives a bar, for the layout it is in.
    private struct SidecarBarPadding: ViewModifier {
        @Environment(\.sidecarPluginLayout) private var layout

        func body(content: Content) -> some View {
            switch layout {
            case .picker:
                content
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
            case .rows:
                content
            }
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
