// The README's production localization example, verbatim, so the README cannot drift from the
// code.
#if DEBUG
    import DebugDrawer
    import DebugDrawerLocalization
    import DebugDrawerReceiver
    import Foundation
    import SwiftUI
    import Testing

    @MainActor
    final class ProductionLocalizationReview {
        let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
        let receiver: DebugDrawerReceiver

        init(container: URL) throws {
            receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
            receiver.enable(.localizationReview())
            try receiver.start()
        }
    }

    struct SettingsHeader: View {
        let itemCount: Int

        var body: some View {
            VStack {
                Text(LocalizationReview.shared.localizedString("settings.title"))
                Text(LocalizationReview.shared.localizedString("\(itemCount) items"))
            }
        }
    }

    @MainActor
    @Suite("README examples")
    struct READMEExamplesTests {
        @Test(
            "Production builds: localization review: served once a session opens, showing translations until the session sets a mode",
            .timeLimit(.minutes(1))
        )
        func productionLocalizationReview() async throws {
            let container = FileManager.default.temporaryDirectory.appending(path: "READMELocalization-\(UUID().uuidString)")
            let review = try ProductionLocalizationReview(container: container)
            defer { review.receiver.stop() }
            _ = SettingsHeader(itemCount: 3).localizationReview()

            let appDirectory = AppGroupStoreLayout.appDirectory(inStore: container.appending(path: "DebugDrawer"))
            let snapshotFile = AppGroupStoreLayout(directory: appDirectory).snapshotFile(for: LocalizationReview.pluginID)
            let servedBeforeSession = FileManager.default.fileExists(atPath: snapshotFile.path)
            review.sessions.perform(.open(duration: 60))
            defer { review.sessions.end() }

            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: appDirectory)
            let modes = try await sidecar.connect(
                toPlugin: LocalizationReview.pluginID, snapshot: LocalizationReview.Snapshot.self, command: LocalizationReview.Command.self
            )
            #expect(review.receiver.enabledCapabilities == [LocalizationReview.pluginID])
            #expect(!servedBeforeSession)
            #expect(modes.snapshot == LocalizationReview.Snapshot(mode: .standard))
            #expect(LocalizationReview.shared.localizedString("\(3) items") == "3 items")
        }
    }
#endif
