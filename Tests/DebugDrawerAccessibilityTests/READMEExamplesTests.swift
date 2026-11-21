// The README's production accessibility example, verbatim, so the README cannot drift from the
// code.
#if DEBUG
    import DebugDrawer
    import DebugDrawerAccessibility
    import DebugDrawerReceiver
    import Foundation
    import SwiftUI
    import Testing

    @MainActor
    final class ProductionAccessibilityReview {
        let sessions = DebugDrawerSessions(maximumDuration: 15 * 60)
        let receiver: DebugDrawerReceiver

        init(container: URL) throws {
            receiver = DebugDrawerReceiver(directory: container.appending(path: "DebugDrawer"), sessions: sessions)
            receiver.enable(.accessibilityEnvironmentOverrides())
            try receiver.start()
        }
    }

    struct ReviewedRoot: View {
        var body: some View {
            Text("Order history")
                .accessibilityEnvironmentOverrides()
        }
    }

    @MainActor
    @Suite("README examples")
    struct READMEExamplesTests {
        @Test("Production builds: accessibility overrides: served once a session opens, none set until the session sets one", .timeLimit(.minutes(1)))
        func productionAccessibilityOverrides() async throws {
            let container = FileManager.default.temporaryDirectory.appending(path: "READMEAccessibility-\(UUID().uuidString)")
            let review = try ProductionAccessibilityReview(container: container)
            defer { review.receiver.stop() }
            _ = ReviewedRoot().body

            let appDirectory = AppGroupStoreLayout.appDirectory(inStore: container.appending(path: "DebugDrawer"))
            let snapshotFile = AppGroupStoreLayout(directory: appDirectory).snapshotFile(for: AccessibilityEnvironmentOverrides.pluginID)
            let servedBeforeSession = FileManager.default.fileExists(atPath: snapshotFile.path)
            review.sessions.perform(.open(duration: 60))
            defer { review.sessions.end() }

            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: appDirectory)
            let environment = try await sidecar.connect(
                toPlugin: AccessibilityEnvironmentOverrides.pluginID,
                snapshot: AccessibilityEnvironmentOverrides.Snapshot.self,
                command: AccessibilityEnvironmentOverrides.Command.self
            )
            #expect(review.receiver.enabledCapabilities == [AccessibilityEnvironmentOverrides.pluginID])
            #expect(!servedBeforeSession)
            #expect(environment.snapshot == AccessibilityEnvironmentOverrides.Snapshot())
        }
    }
#endif
