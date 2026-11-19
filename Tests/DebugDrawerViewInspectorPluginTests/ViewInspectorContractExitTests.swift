// The interception contract's checks (DebugDrawerInterceptionContract). Exit tests start a child
// process, which only the Mac's test runs can do. The overlays, the animation speed and the render
// tracker are the process's one set, which other suites read at the same time, so each check runs
// in a child of its own. On the Mac the plugin swizzles nothing (clicks are watched through an
// NSEvent monitor the Click Indicators switch starts); iOS's UIWindow.sendEvent(_:) swizzle is
// checked in ClickIndicatorSwizzleTests, in the simulator, which can't start a child process.
#if os(macOS) && DEBUG
    @testable import DebugDrawer
    import DebugDrawerInterceptionContract
    @testable import DebugDrawerViewInspectorPlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    /// A row whose body is tracked under a name of the test's own.
    private struct ContractRow: View {
        let name: String

        var body: some View {
            Text("row")
                .trackRenders(name)
        }
    }

    /// The View Inspector plugin's side of the contract. What it keeps of the app's is a render
    /// count per name given to `.trackRenders(_:)`; a captured call evaluates a row tracked under
    /// its marker.
    @MainActor
    private struct ViewInspectorContract: UnchangedResultContract, DrawerActivityContract {
        /// What installing turns on, and what the plugin's switches change in the app's windows.
        struct ProcessState: Equatable {
            var isTrackingRenders: Bool
            var isBordersEnabled: Bool
            var isGridEnabled: Bool
            var isClickIndicatorEnabled: Bool
            var animationSpeed: Double
            var isFlashingRenders: Bool
        }

        func install(in drawer: DebugDrawer) {
            drawer.installViewInspector()
        }

        func uninstall(from drawer: DebugDrawer) {
            drawer.unregisterGlobal(id: ViewInspectorPlugin().id)
        }

        func processState() throws -> ProcessState {
            let controller = ViewBorderController.shared
            return ProcessState(
                isTrackingRenders: RenderTracker.shared.isTracking,
                isBordersEnabled: controller.isBordersEnabled,
                isGridEnabled: controller.isGridEnabled,
                isClickIndicatorEnabled: controller.isClickIndicatorEnabled,
                animationSpeed: controller.animationSpeed,
                isFlashingRenders: RenderFlashSetting.shared.isOn
            )
        }

        /// The texts a tracked row shows.
        func makeAppCall() async throws -> [String] {
            try ContractRow(name: "App").inspect().findAll(ViewType.Text.self).map { try $0.string() }
        }

        func limitCapture(to count: Int) {
            RenderTracker.shared.capacity = count
        }

        func makeCapturedCall(_ marker: String) async throws {
            _ = try ContractRow(name: marker).inspect().findAll(ViewType.Text.self)
        }

        func capturedMarkers(through marker: String) async throws -> [String] {
            // A body records as it is evaluated, so there is nothing to wait for.
            RenderTracker.shared.counts.keys.filter { $0 != "App" }
        }

        func capturedCount() -> Int {
            RenderTracker.shared.counts.count
        }

        /// The drawer open with the View Inspector plugin's own view, Flash Renders switched on
        /// and off: none of the drawer's views is tracked.
        func makeDrawerCall(_ marker: String) async throws {
            let presentation = DrawerPresentation()
            presentation.isOpen = true
            _ = try DebugDrawerOverlay(drawer: .shared, presentation: presentation).inspect().findAll(ViewType.Text.self)
            let plugin = try ViewInspectorPluginView(transport: .direct(to: ViewInspectorModel.shared)).inspect()
            try plugin.find(ViewType.Toggle.self) { try $0.labelView().text().string() == "Flash Renders" }.tap()
            _ = try ViewInspectorPluginView(transport: .direct(to: ViewInspectorModel.shared)).inspect().findAll(ViewType.Text.self)
            RenderFlashSetting.shared.isOn = false
        }
    }

    @Suite("The View Inspector plugin keeps the interception contract, in a child process", .timeLimit(.minutes(1)))
    struct ViewInspectorContractExitTests {
        @Test("Installing the View Inspector plugin twice, or in a second drawer, changes the process as installing it once does")
        func idempotentInstall() async {
            await #expect(processExitsWith: .success) {
                try await ViewInspectorContract().checkIdempotentInstall()
            }
        }

        @Test("A tracked view's render counts once with the View Inspector plugin installed twice")
        func capturesOnceInstalledTwice() async {
            await #expect(processExitsWith: .success) {
                try await ViewInspectorContract().checkCapturesOnceInstalledTwice()
            }
        }

        @Test("Removing the View Inspector plugin from the last drawer holding it puts back what installing changed")
        func reversibleUninstall() async {
            await #expect(processExitsWith: .success) {
                try await ViewInspectorContract().checkReversibleUninstall()
            }
        }

        @Test("The View Inspector plugin removed forgets its render counts and counts nothing until installed again")
        func capturesNothingUninstalled() async {
            await #expect(processExitsWith: .success) {
                try await ViewInspectorContract().checkCapturesNothingUninstalled()
            }
        }

        @Test("A tracked view shows the same with the View Inspector plugin installed as without")
        func unchangedResult() async {
            await #expect(processExitsWith: .success) {
                try await ViewInspectorContract().checkUnchangedResult()
            }
        }

        @Test("The render counts keep at most their capacity of names, the newest")
        func boundedCapture() async {
            await #expect(processExitsWith: .success) {
                try await ViewInspectorContract().checkBoundedCapture()
            }
        }

        @Test("Opening the drawer and using the View Inspector plugin counts no render")
        func leavesOutDrawerActivity() async {
            await #expect(processExitsWith: .success) {
                try await ViewInspectorContract().checkLeavesOutDrawerActivity()
            }
        }
    }
#endif
