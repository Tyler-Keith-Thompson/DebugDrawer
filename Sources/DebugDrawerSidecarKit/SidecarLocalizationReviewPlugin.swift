import DebugDrawer
import DebugDrawerLocalization
import Foundation
import SwiftUI

// The sidecar's half of localization review (DD-123): a picker of the modes the app's strings can
// show in (`LocalizationReview`, in DebugDrawerLocalization) for the strings it reads through the
// review, back to standard as the session ends. It ships in the kit, as the modes are the
// library's own, so every sidecar would draw the same picker.

#if DEBUG
    extension DebugDrawerSidecarPlugin {
        /// How the app shows the strings it reads through `LocalizationReview`
        /// (`DebugDrawerReceiverCapability.localizationReview(_:)`): standard, pseudo-localized or
        /// as their keys, for the session.
        @MainActor public static var localizationReview: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: LocalizationReview.pluginID, title: "Strings", icon: "character.bubble",
                snapshot: LocalizationReview.Snapshot.self, command: LocalizationReview.Command.self
            ) { transport in
                LocalizationReviewSidecarPlugin(transport: transport)
            }
        }
    }

    /// The app's review mode, set from the sidecar.
    struct LocalizationReviewSidecarPlugin: DebugDrawerPlugin {
        let transport: DebugDrawerPluginTransport<LocalizationReview.Snapshot, LocalizationReview.Command>
        let title = "Strings"
        let icon = "character.bubble"

        var body: some View {
            LocalizationReviewTransportView(transport: transport)
        }
    }

    /// The mode over the capability's snapshot, sending what the view asks.
    struct LocalizationReviewTransportView: View {
        @ObservedObject var transport: DebugDrawerPluginTransport<LocalizationReview.Snapshot, LocalizationReview.Command>

        var body: some View {
            LocalizationReviewSidecarView(snapshot: transport.snapshot) { transport.send($0) }
        }
    }

    /// A picker of the modes, over the app's. A function of the snapshot and the send action.
    struct LocalizationReviewSidecarView: View {
        let snapshot: LocalizationReview.Snapshot
        let send: (LocalizationReview.Command) -> Void

        var body: some View {
            DebugDrawerSection("Review Mode") {
                DebugDrawerRow("Strings") {
                    Picker("Strings", selection: Binding { snapshot.mode } set: { send(.setMode($0)) }) {
                        ForEach(Localization.Mode.allCases, id: \.self) { mode in
                            Text(mode.title).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .accessibilityLabel("Strings")
                }
            } footer: {
                Text("Covers the strings the app reads through its localization review; back to standard as the session ends.")
            }
        }
    }

    extension Localization.Mode {
        /// The mode as the picker names it.
        fileprivate var title: String {
            switch self {
            case .standard: "Standard"
            case .pseudoLocalized: "Pseudo-localized"
            case .showingKeys: "Keys"
            }
        }
    }
#else
    // The release stand-in: the same member, over a plugin that draws nothing; a release build's
    // transports connect to nothing anyway.

    extension DebugDrawerSidecarPlugin {
        /// How the app shows its reviewed strings; release builds show nothing.
        @MainActor public static var localizationReview: DebugDrawerSidecarPlugin {
            DebugDrawerSidecarPlugin(
                id: LocalizationReview.pluginID, title: "Strings", icon: "character.bubble",
                snapshot: LocalizationReview.Snapshot.self, command: LocalizationReview.Command.self
            ) { _ in
                LocalizationReviewSidecarPlugin()
            }
        }
    }

    /// Draws nothing.
    struct LocalizationReviewSidecarPlugin: DebugDrawerPlugin {
        let title = "Strings"
        let icon = "character.bubble"

        var body: some View {
            EmptyView()
        }
    }
#endif
