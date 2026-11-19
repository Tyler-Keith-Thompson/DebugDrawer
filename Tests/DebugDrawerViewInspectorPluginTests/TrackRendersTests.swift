// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    import Combine
    @testable import DebugDrawer
    @testable import DebugDrawerViewInspectorPlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    /// What the hosted screen shows: one value for the tracked view, one for its sibling.
    @MainActor
    private final class ScreenInputs: ObservableObject {
        @Published var tracked = 0
        @Published var sibling = 0
    }

    /// A value whose body is tracked under `name`.
    private struct TrackedValue: View {
        let value: Int
        let name: String

        var body: some View {
            Text("\(value)")
                .trackRenders(name)
        }
    }

    /// Two tracked siblings, each fed one of the inputs.
    private struct Screen: View {
        @ObservedObject var inputs: ScreenInputs
        let trackedName: String
        let siblingName: String

        var body: some View {
            VStack {
                TrackedValue(value: inputs.tracked, name: trackedName)
                TrackedValue(value: inputs.sibling, name: siblingName)
            }
        }
    }

    // The tracker is the app's one shared tracker, which other suites record into at the same
    // time; each test tracks names of its own, so they never share a count.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct TrackRendersTests {
        @Test("A tracked view's count goes up when its input changes, and stays put when only its sibling's does")
        func countsFollowTheViewsOwnInput() async {
            let trackedName = "Tracked-\(UUID().uuidString)"
            let siblingName = "Sibling-\(UUID().uuidString)"
            let inputs = ScreenInputs()
            let tracker = RenderTracker.shared
            // Renders are counted while the plugin is installed.
            DebugDrawer.shared.installViewInspector()
            let sut = Screen(inputs: inputs, trackedName: trackedName, siblingName: siblingName)
            ViewHosting.host(view: sut)
            defer { ViewHosting.expel() }
            for await _ in tracker.$entries.values where tracker.counts[siblingName] != nil {
                break
            }
            let trackedAtFirst = tracker.counts[trackedName] ?? 0
            let siblingAtFirst = tracker.counts[siblingName] ?? 0

            inputs.sibling += 1
            for await _ in tracker.$entries.values where tracker.counts[siblingName, default: 0] > siblingAtFirst {
                break
            }
            let trackedAfterSibling = tracker.counts[trackedName] ?? 0
            inputs.tracked += 1
            for await _ in tracker.$entries.values where tracker.counts[trackedName, default: 0] > trackedAtFirst {
                break
            }
            let actual = tracker.counts[trackedName] ?? 0

            #expect(trackedAfterSibling == trackedAtFirst)
            #expect(actual == trackedAtFirst + 1)
        }

        @Test("Opening the drawer and using the View Inspector plugin records no renders")
        func drawerIsNeverCounted() throws {
            let drawer = DebugDrawer.shared
            let flashesWereOn = RenderFlashSetting.shared.isOn
            drawer.installViewInspector()
            let presentation = DrawerPresentation()
            presentation.isOpen = true
            // Every body evaluated below runs in this one main-actor turn, so no other test
            // records in between.
            let before = RenderTracker.shared.counts
            let sut = DebugDrawerOverlay(drawer: drawer, presentation: presentation)

            let app = try sut.inspect()
            let texts = app.findAll(ViewType.Text.self).compactMap { try? $0.string() }
            let plugin = try ViewInspectorPluginView(transport: .direct(to: ViewInspectorModel.shared)).inspect()
            let pluginTexts = plugin.findAll(ViewType.Text.self).compactMap { try? $0.string() }
            try plugin.find(ViewType.Toggle.self) { try $0.labelView().text().string() == "Flash Renders" }.tap()
            _ = try ViewInspectorPluginView(transport: .direct(to: ViewInspectorModel.shared)).inspect().findAll(ViewType.Text.self)
            let actual = RenderTracker.shared.counts
            RenderFlashSetting.shared.isOn = flashesWereOn

            #expect(texts.contains("View Inspector"))
            #expect(pluginTexts.contains("SwiftUI Renders"))
            #expect(actual == before)
        }
    }
#endif
