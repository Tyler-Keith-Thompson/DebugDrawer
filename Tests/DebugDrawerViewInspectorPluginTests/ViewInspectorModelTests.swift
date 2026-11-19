#if DEBUG
    import Combine
    import DebugDrawer
    @testable import DebugDrawerViewInspectorPlugin
    import Foundation
    import Testing

    /// Overlays that draw nothing: they keep the settings they are given and count installs.
    @MainActor
    private final class FakeOverlays: ViewInspectorOverlayService {
        @Published var overlaySettings = ViewInspectorOverlaySettings()
        private(set) var installCount = 0
        private(set) var uninstallCount = 0

        func install() {
            installCount += 1
        }

        func uninstall() {
            uninstallCount += 1
            overlaySettings.isBordersEnabled = false
            overlaySettings.isGridEnabled = false
            overlaySettings.isClickIndicatorEnabled = false
            overlaySettings.animationSpeed = 1
        }
    }

    /// A key window whose hierarchy is `hierarchy`, or no key window when it is `nil`.
    @MainActor
    private final class FakeHierarchyReader: ViewHierarchyReader {
        var hierarchy: ViewNode?
        private(set) var readCount = 0

        init(_ hierarchy: ViewNode?) {
            self.hierarchy = hierarchy
        }

        func keyWindowHierarchy() -> ViewNode? {
            readCount += 1
            return hierarchy
        }
    }

    // The model is read and driven here as an out-of-process reader would: through its snapshot,
    // encoded and decoded, and commands, encoded and decoded, with no view. Its overlays and its
    // key window are fakes; its render tracker and flash setting are real ones of its own, never
    // the process's shared ones.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ViewInspectorModelTests {
        @Test("A snapshot with overlays on, render counts, flashing and a nested hierarchy encodes to JSON and decodes equal")
        func snapshotRoundTrips() async throws {
            let button = ViewNode(
                className: "NSButton", frame: CGRect(x: 16, y: 8, width: 88, height: 32),
                accessibilityLabel: "Save", accessibilityRole: "AXButton", isHidden: false, alpha: 0.5,
                hasClipping: true, cornerRadius: 6, backgroundColor: "#0A84FF", constraintCount: 4,
                subviewCount: 0, children: []
            )
            let root = ViewNode(
                className: "NSHostingView", frame: CGRect(x: 0, y: 0, width: 480, height: 320),
                accessibilityLabel: nil, accessibilityRole: nil, isHidden: true, alpha: 1,
                hasClipping: false, cornerRadius: 0, backgroundColor: nil, constraintCount: 0,
                subviewCount: 1, children: [button]
            )
            let tracker = RenderTracker()
            let sut = ViewInspectorModel(
                overlays: FakeOverlays(),
                hierarchyReader: FakeHierarchyReader(root),
                renderTracker: tracker,
                renderFlash: RenderFlashSetting()
            )
            sut.perform(ViewInspectorCommand(.overlays(.setBordersEnabled(true))))
            sut.perform(ViewInspectorCommand(.overlays(.setGridEnabled(true))))
            sut.perform(ViewInspectorCommand(.overlays(.setGridColor(.green))))
            sut.perform(ViewInspectorCommand(.overlays(.setAnimationSpeed(2.5))))
            sut.perform(ViewInspectorCommand(.renders(.setFlashing(true))))
            sut.perform(ViewInspectorCommand(.hierarchy(.snapshot)))
            tracker.record("FeedView")
            tracker.record("FeedView")
            tracker.record("AvatarView")
            for await entries in tracker.$entries.values where !entries.isEmpty {
                break
            }
            let snapshot = sut.snapshot
            let expectedCounts = [RenderTracker.Entry(id: "FeedView", count: 2), RenderTracker.Entry(id: "AvatarView", count: 1)]

            let encoded = try JSONEncoder().encode(snapshot)
            let actual = try JSONDecoder().decode(ViewInspectorSnapshot.self, from: encoded)

            #expect(actual == snapshot)
            #expect(actual.overlays.isBordersEnabled)
            #expect(actual.overlays.gridColor == .green)
            #expect(actual.overlays.animationSpeed == 2.5)
            #expect(actual.isFlashingRenders)
            #expect(actual.renderCounts == expectedCounts)
            #expect(actual.hierarchy == root)
            #expect(actual.hierarchy?.children.first?.backgroundColor == "#0A84FF")
        }

        @Test("Each overlay command, encoded to JSON and decoded, sets its switch in the overlays through a direct transport")
        func overlayCommandsRoundTrip() throws {
            let overlays = FakeOverlays()
            let sut = DebugDrawerPluginTransport.direct(to: ViewInspectorModel(
                overlays: overlays,
                hierarchyReader: FakeHierarchyReader(nil),
                renderTracker: RenderTracker(),
                renderFlash: RenderFlashSetting()
            ))
            let commands = [
                ViewInspectorCommand(.overlays(.setBordersEnabled(true))),
                ViewInspectorCommand(.overlays(.setGridEnabled(true))),
                ViewInspectorCommand(.overlays(.setGridSpacing(16))),
                ViewInspectorCommand(.overlays(.setGridColor(.red))),
                ViewInspectorCommand(.overlays(.setGridOpacity(0.3))),
                ViewInspectorCommand(.overlays(.setClickIndicatorEnabled(true))),
                ViewInspectorCommand(.overlays(.setAnimationSpeed(10)))
            ]
            let expected = ViewInspectorOverlaySettings(
                isBordersEnabled: true, isGridEnabled: true, gridSpacing: 16, gridColor: .red, gridOpacity: 0.3,
                isClickIndicatorEnabled: true, animationSpeed: 10
            )

            for command in commands {
                let decoded = try JSONDecoder().decode(ViewInspectorCommand.self, from: JSONEncoder().encode(command))
                sut.send(decoded)
            }

            #expect(overlays.overlaySettings == expected)
            #expect(sut.snapshot.overlays == expected)
        }

        @Test("Flash and Reset change the model's own flash setting and render counts")
        func renderCommands() async {
            let tracker = RenderTracker()
            let flash = RenderFlashSetting()
            let sut = ViewInspectorModel(
                overlays: FakeOverlays(), hierarchyReader: FakeHierarchyReader(nil), renderTracker: tracker, renderFlash: flash
            )
            tracker.record("FeedView")
            for await entries in tracker.$entries.values where !entries.isEmpty {
                break
            }

            sut.perform(ViewInspectorCommand(.renders(.setFlashing(true))))
            sut.perform(ViewInspectorCommand(.renders(.reset)))

            #expect(flash.isOn)
            #expect(tracker.counts.isEmpty)
            #expect(sut.snapshot.renderCounts.isEmpty)
            #expect(sut.snapshot.isFlashingRenders)
        }

        @Test("Snapshot reads the key window's hierarchy, a snapshot with no key window keeps what is shown, and Collapse lets it go")
        func hierarchyCommands() {
            let root = ViewNode(
                className: "UIView", frame: CGRect(x: 0, y: 0, width: 390, height: 844),
                accessibilityLabel: nil, accessibilityRole: nil, isHidden: false, alpha: 1,
                hasClipping: false, cornerRadius: 0, backgroundColor: "#FFFFFF", constraintCount: 0,
                subviewCount: 0, children: []
            )
            let reader = FakeHierarchyReader(root)
            let sut = ViewInspectorModel(
                overlays: FakeOverlays(), hierarchyReader: reader, renderTracker: RenderTracker(), renderFlash: RenderFlashSetting()
            )
            let beforeSnapshot = sut.snapshot.hierarchy

            sut.perform(ViewInspectorCommand(.hierarchy(.snapshot)))
            let afterSnapshot = sut.snapshot.hierarchy
            reader.hierarchy = nil
            sut.perform(ViewInspectorCommand(.hierarchy(.snapshot)))
            let withNoKeyWindow = sut.snapshot.hierarchy
            sut.perform(ViewInspectorCommand(.hierarchy(.collapse)))
            let actual = sut.snapshot.hierarchy

            #expect(beforeSnapshot == nil)
            #expect(afterSnapshot == root)
            #expect(withNoKeyWindow == root)
            #expect(reader.readCount == 2)
            #expect(actual == nil)
        }

        @Test("Installed in two drawers, the model starts once per drawer and stops only when the last uninstalls")
        func installCountsDrawers() async {
            let overlays = FakeOverlays()
            let tracker = RenderTracker()
            let flash = RenderFlashSetting()
            let sut = ViewInspectorModel(
                overlays: overlays,
                hierarchyReader: FakeHierarchyReader(ViewNode(
                    className: "NSView", frame: .zero, accessibilityLabel: nil, accessibilityRole: nil, isHidden: false,
                    alpha: 1, hasClipping: false, cornerRadius: 0, backgroundColor: nil, constraintCount: 0,
                    subviewCount: 0, children: []
                )),
                renderTracker: tracker,
                renderFlash: flash
            )
            let first = DebugDrawer()
            let second = DebugDrawer()
            let neverInstalled = DebugDrawer()

            sut.install(in: ObjectIdentifier(first))
            sut.install(in: ObjectIdentifier(second))
            let trackingWhileInstalled = tracker.isTracking
            sut.perform(ViewInspectorCommand(.overlays(.setBordersEnabled(true))))
            sut.perform(ViewInspectorCommand(.renders(.setFlashing(true))))
            sut.perform(ViewInspectorCommand(.hierarchy(.snapshot)))
            tracker.record("FeedView")
            for await entries in tracker.$entries.values where !entries.isEmpty {
                break
            }
            sut.uninstall(from: ObjectIdentifier(neverInstalled))
            sut.uninstall(from: ObjectIdentifier(first))
            let afterFirstUninstall = sut.snapshot
            let uninstallsAfterFirst = overlays.uninstallCount
            sut.uninstall(from: ObjectIdentifier(second))
            let actual = sut.snapshot

            #expect(overlays.installCount == 2)
            #expect(trackingWhileInstalled)
            #expect(uninstallsAfterFirst == 0)
            #expect(afterFirstUninstall.overlays.isBordersEnabled)
            #expect(afterFirstUninstall.hierarchy != nil)
            #expect(overlays.uninstallCount == 1)
            #expect(!tracker.isTracking)
            #expect(tracker.counts.isEmpty)
            #expect(actual == ViewInspectorSnapshot())
        }

        @Test("A switch changed in the overlays, rather than through a command, reaches the snapshot and announces the change")
        func outsideChangesReachTheSnapshot() {
            let overlays = FakeOverlays()
            let sut = ViewInspectorModel(
                overlays: overlays, hierarchyReader: FakeHierarchyReader(nil), renderTracker: RenderTracker(), renderFlash: RenderFlashSetting()
            )
            var announcements = 0
            let subscription = sut.objectWillChange.sink { announcements += 1 }

            overlays.overlaySettings.isGridEnabled = true
            subscription.cancel()
            let actual = sut.snapshot.overlays.isGridEnabled

            #expect(announcements == 1)
            #expect(actual)
        }

        @Test("The controller's overlay settings read back what was set, and setting them changes only what differs")
        func controllerSettingsRoundTrip() {
            let sut = ViewBorderController(appWindows: { [] })
            let expected = ViewInspectorOverlaySettings(gridSpacing: 24, gridColor: .gray, gridOpacity: 0.4)
            var announcements = 0
            let subscription = sut.objectWillChange.sink { announcements += 1 }

            sut.overlaySettings = expected
            let announcementsAfterChange = announcements
            sut.overlaySettings = expected
            subscription.cancel()
            let actual = sut.overlaySettings

            #expect(actual == expected)
            #expect(sut.gridSpacing == 24)
            #expect(sut.gridColor == .gray)
            #expect(announcementsAfterChange == 3)
            #expect(announcements == 3)
        }
    }
#endif
