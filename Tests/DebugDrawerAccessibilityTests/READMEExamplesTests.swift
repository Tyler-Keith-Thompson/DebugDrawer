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
        @Test("Production builds: accessibility overrides: the overrides are served, none set until a session sets one", .timeLimit(.minutes(1)))
        func productionAccessibilityOverrides() async throws {
            let container = FileManager.default.temporaryDirectory.appending(path: "READMEAccessibility-\(UUID().uuidString)")
            let review = try ProductionAccessibilityReview(container: container)
            defer { review.receiver.stop() }
            _ = ReviewedRoot().body

            let appDirectory = AppGroupStoreLayout.appDirectory(inStore: container.appending(path: "DebugDrawer"))

            let sidecar = try DebugDrawerAppGroupStoreTransport(directory: appDirectory)
            let environment = try await sidecar.connect(
                toPlugin: AccessibilityEnvironmentOverrides.pluginID,
                snapshot: AccessibilityEnvironmentOverrides.Snapshot.self,
                command: AccessibilityEnvironmentOverrides.Command.self
            )
            #expect(review.receiver.enabledCapabilities == [AccessibilityEnvironmentOverrides.pluginID])
            #expect(environment.snapshot == AccessibilityEnvironmentOverrides.Snapshot())
        }
    }
#endif
