import DebugDrawer
import DebugDrawerLocalization
import DebugDrawerSidecarKit
import SwiftUI

extension DebugDrawerSidecarPlugin {
    /// The host's localization review mode (`DebugDrawerReceiverCapability.localizationReview`).
    @MainActor static var localizationReview: DebugDrawerSidecarPlugin {
        DebugDrawerSidecarPlugin(
            id: LocalizationReview.pluginID, title: "Strings", icon: "character.bubble",
            snapshot: LocalizationReview.Snapshot.self, command: LocalizationReview.Command.self
        ) { transport in
            LocalizationReviewPlugin(transport: transport)
        }
    }
}

/// How the host shows the strings it reads through `LocalizationReview`, for the session.
struct LocalizationReviewPlugin: DebugDrawerPlugin {
    let transport: DebugDrawerPluginTransport<LocalizationReview.Snapshot, LocalizationReview.Command>
    let title = "Strings"
    let icon = "character.bubble"

    var body: some View {
        LocalizationReviewView(transport: transport)
    }
}

private struct LocalizationReviewView: View {
    @ObservedObject var transport: DebugDrawerPluginTransport<LocalizationReview.Snapshot, LocalizationReview.Command>

    var body: some View {
        DebugDrawerSection("Review mode") {
            DebugDrawerRow("Strings") {
                Picker("Strings", selection: Binding(get: { transport.snapshot.mode }, set: { transport.send(.setMode($0)) })) {
                    Text("Standard").tag(Localization.Mode.standard)
                    Text("Pseudo-localized").tag(Localization.Mode.pseudoLocalized)
                    Text("Keys").tag(Localization.Mode.showingKeys)
                }
                .labelsHidden()
            }
        } footer: {
            Text("Back to standard as the session ends.")
        }
    }
}
