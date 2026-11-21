// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    import Combine
    @testable import DebugDrawer
    import DebugDrawerTestSupport
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

    /// Overlays that draw nothing and change nothing in the app's windows.
    @MainActor
    private final class StillOverlays: ViewInspectorOverlayService {
        @Published var overlaySettings = ViewInspectorOverlaySettings()

        func install() {}

        func uninstall() {}
    }

    /// No key window to read.
    @MainActor
    private struct NoHierarchy: ViewHierarchyReader {
        func keyWindowHierarchy() -> ViewNode? {
            nil
        }
    }

    // Each test installs the plugin on a drawer of its own, over a tracker of its own, and removes
    // it before it ends; the suite takes turns with the others that install it.
    extension RenderTrackingInstalls {
        @MainActor
        @Suite(.timeLimit(.minutes(1)))
        struct TrackRendersTests {
            @Test("A tracked view's count goes up when its input changes, and stays put when only its sibling's does")
            func countsFollowTheViewsOwnInput() async throws {
                let suite = temporarySuiteName("TrackRendersTests")
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let trackedName = "Tracked-\(UUID().uuidString)"
                let siblingName = "Sibling-\(UUID().uuidString)"
                let inputs = ScreenInputs()
                let tracker = RenderTracker()
                let plugin = ViewInspectorPlugin(model: ViewInspectorModel(
                    overlays: StillOverlays(), hierarchyReader: NoHierarchy(), renderTracker: tracker, renderFlash: RenderFlashSetting()
                ))
                let drawer = DebugDrawer(defaults: defaults)
                // Renders are counted while the plugin is installed.
                drawer.registerGlobal(plugin)
                defer { drawer.unregisterGlobal(id: plugin.id) }
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
                let suite = temporarySuiteName("TrackRendersTests")
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let tracker = RenderTracker()
                let model = ViewInspectorModel(
                    overlays: StillOverlays(), hierarchyReader: NoHierarchy(), renderTracker: tracker, renderFlash: RenderFlashSetting()
                )
                let plugin = ViewInspectorPlugin(model: model)
                let drawer = DebugDrawer(defaults: defaults)
                drawer.registerGlobal(plugin)
                defer { drawer.unregisterGlobal(id: plugin.id) }
                let presentation = DrawerPresentation()
                presentation.isOpen = true
                let sut = DebugDrawerOverlay(drawer: drawer, presentation: presentation)

                let app = try sut.inspect()
                let texts = app.findAll(ViewType.Text.self).compactMap { try? $0.string() }
                let pluginView = try ViewInspectorPluginView(transport: .direct(to: model)).inspect()
                let pluginTexts = pluginView.findAll(ViewType.Text.self).compactMap { try? $0.string() }
                try pluginView.find(ViewType.Toggle.self) { try $0.labelView().text().string() == "Flash Renders" }.tap()
                _ = try ViewInspectorPluginView(transport: .direct(to: model)).inspect().findAll(ViewType.Text.self)
                let actual = tracker.counts

                #expect(texts.contains("View Inspector"))
                #expect(pluginTexts.contains("SwiftUI Renders"))
                #expect(actual.isEmpty)
            }

            @Test("""
            Installed on a drawer of its own, the plugin's tracker gets the counts and the shared one none; once removed, the shared \
            drawer's plugin gets them again
            """)
            func latestInstallGetsTheCounts() throws {
                let suite = temporarySuiteName("TrackRendersTests")
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let name = "Routed-\(UUID().uuidString)"
                let tracker = RenderTracker()
                let plugin = ViewInspectorPlugin(model: ViewInspectorModel(
                    overlays: StillOverlays(), hierarchyReader: NoHierarchy(), renderTracker: tracker, renderFlash: RenderFlashSetting()
                ))
                let drawer = DebugDrawer(defaults: defaults)
                // The app's drawer holds the plugin first, as an app installs it at launch.
                DebugDrawer.shared.installViewInspector()
                drawer.registerGlobal(plugin)

                _ = try TrackedValue(value: 1, name: name).inspect().findAll(ViewType.Text.self)
                let ownWhileInstalled = tracker.counts[name, default: 0]
                let sharedWhileInstalled = RenderTracker.shared.counts[name, default: 0]
                drawer.unregisterGlobal(id: plugin.id)
                _ = try TrackedValue(value: 2, name: name).inspect().findAll(ViewType.Text.self)
                let ownAfterRemoval = tracker.counts[name, default: 0]
                let sharedAfterRemoval = RenderTracker.shared.counts[name, default: 0]

                #expect(ownWhileInstalled > 0)
                #expect(sharedWhileInstalled == 0)
                #expect(ownAfterRemoval == 0)
                #expect(sharedAfterRemoval > 0)
            }
        }
    }
#endif
