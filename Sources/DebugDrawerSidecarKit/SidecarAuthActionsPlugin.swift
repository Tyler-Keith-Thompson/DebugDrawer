import DebugDrawer
import Foundation
import SwiftUI

// The sidecar's half of the auth actions (DD-117): the actions the app registered
// (`DebugDrawerAuthActions`, in the receiver), a button each and what its last run came to. The
// button leaves the request for the app and then brings the app forward, where its receiver
// performs it, as the Scenarios plugin's Launch does. It ships in the kit, beside Scenarios, for
// the same reasons: the actions describe themselves, so every sidecar would draw the same buttons,
// and opening the app is the kit's own (`DebugDrawerSidecarApp.open(url:)`), reached through the
// environment the kit's host sets. The plugin never sees a token: the snapshot holds none.

#if DEBUG
    extension DebugDrawerSidecarPlugin {
        /// The auth actions the app registered (`DebugDrawerReceiverCapability.authActions(_:launchURL:)`),
        /// a button each, which sends the request and brings the app to the foreground, where its
        /// handler runs, and what each action's last run came to.
        @MainActor public static var authActions: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: DebugDrawerAuthActions.pluginID, title: "Auth", icon: "person.badge.key",
                snapshot: DebugDrawerAuthActions.Snapshot.self, command: DebugDrawerAuthActions.Command.self
            ) { transport in
                AuthActionsPlugin(transport: transport)
            }
        }
    }

    /// The app's auth actions, asked for from the sidecar.
    struct AuthActionsPlugin: DebugDrawerPlugin {
        let transport: DebugDrawerPluginTransport<DebugDrawerAuthActions.Snapshot, DebugDrawerAuthActions.Command>
        let title = "Auth"
        let icon = "person.badge.key"

        var body: some View {
            AuthActionsView(transport: transport)
        }
    }

    /// What became of the last request the sidecar made.
    enum AuthActionRequestStatus: Equatable {
        case idle
        case opening(title: String)
        case opened(title: String)
        case notOpened(title: String)

        /// The status line, or `nil` before any request.
        var text: String? {
            switch self {
            case .idle: nil
            case let .opening(title): "Sent \(title); opening the app…"
            case let .opened(title): "Sent \(title); the app runs it in the foreground"
            case let .notOpened(title): "Sent \(title); open the app to run it"
            }
        }
    }

    /// Each action with its button and last run, and what the sidecar's own request came to.
    struct AuthActionsView: View {
        @ObservedObject var transport: DebugDrawerPluginTransport<DebugDrawerAuthActions.Snapshot, DebugDrawerAuthActions.Command>
        @Environment(\.debugDrawerSidecarApp) private var app
        @State private var status = AuthActionRequestStatus.idle

        var body: some View {
            let snapshot = transport.snapshot
            if snapshot.actions.isEmpty {
                DebugDrawerEmptyState("No Auth Actions", systemImage: "person.badge.key") {
                    Text("The app registers no auth action.")
                }
            } else {
                ForEach(snapshot.actions) { entry in
                    AuthActionSection(entry: entry) {
                        request(entry, url: snapshot.launchURL)
                    }
                }
                if let text = status.text {
                    Text(text)
                        .debugDrawerFont(.label)
                        .foregroundStyle(.secondary)
                        .debugDrawerRowPadding()
                        .accessibilityIdentifier("AuthActionRequestStatus")
                }
            }
        }

        /// Leaves the request for the app, then brings the app forward.
        private func request(_ entry: DebugDrawerAuthActions.Entry, url: URL?) {
            transport.send(.perform(action: entry.id))
            status = .opening(title: entry.title)
            Task {
                let opened = await app?.open(url: url) ?? false
                status = opened ? .opened(title: entry.title) : .notOpened(title: entry.title)
            }
        }
    }

    /// One action: its summary, its last run and its button. A function of the entry and the
    /// request action.
    struct AuthActionSection: View {
        let entry: DebugDrawerAuthActions.Entry
        let request: () -> Void

        var body: some View {
            DebugDrawerSection(entry.title) {
                if !entry.summary.isEmpty {
                    Text(entry.summary)
                        .debugDrawerFont(.label)
                        .foregroundStyle(.secondary)
                        .debugDrawerRowPadding()
                }
                DebugDrawerKeyValueRow("Last Run", value: entry.lastRun?.summary ?? "None yet")
                DebugDrawerActionRow {
                    Button(entry.title, action: request)
                        .debugDrawerButtonStyle(.primary)
                        .accessibilityLabel(entry.title)
                }
            }
        }
    }

    extension DebugDrawerAuthActions.Run {
        /// The run as the sidecar lists it: where it is, its number and when it started.
        var summary: String {
            let time = started.formatted(date: .omitted, time: .standard)
            return switch status {
            case .running: "Running (#\(number), \(time))"
            case .succeeded: "Succeeded (#\(number), \(time))"
            case let .failed(message): "Failed: \(message) (#\(number), \(time))"
            }
        }
    }
#else
    // The release stand-in: the same member, over a plugin that draws nothing; a release build's
    // transports connect to nothing anyway.

    extension DebugDrawerSidecarPlugin {
        /// The auth actions the app registered; release builds show nothing.
        @MainActor public static var authActions: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: DebugDrawerAuthActions.pluginID, title: "Auth", icon: "person.badge.key",
                snapshot: DebugDrawerAuthActions.Snapshot.self, command: DebugDrawerAuthActions.Command.self
            ) { _ in
                AuthActionsPlugin()
            }
        }
    }

    /// Draws nothing.
    struct AuthActionsPlugin: DebugDrawerPlugin {
        let title = "Auth"
        let icon = "person.badge.key"

        var body: some View {
            EmptyView()
        }
    }
#endif
