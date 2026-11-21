// The controller holds `.debugGrid()`'s probes weakly: a probe whose last owner lets go must be
// freed at once and no longer listed, without waiting for an autorelease pool to drain (DD-281).
// The first test drains none. AppKit and UIKit autorelease a view they add to or remove from a
// superview, so the second drains a pool of its own around each of those calls only: every call
// into the controller (adding the probe, listing the probes) runs outside one, so a probe the
// controller autoreleased would still be alive when the test checks.
// Each test makes its own controller over a window it never shows, so the shared one is left alone.
#if os(macOS) && DEBUG
    import AppKit
    @testable import DebugDrawerViewInspectorPlugin
    import Testing

    @MainActor
    @Suite
    struct GridProbeLifetimeTests {
        @Test("A grid probe the controller added and listed is freed once its last owner lets go, with no autorelease pool drained")
        func probeIsFreedWithNoPool() {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 200), styleMask: [.titled], backing: .buffered, defer: true)
            let sut = ViewBorderController(appWindows: { [window] })
            sut.isGridEnabled = true
            weak var freed: GridProbeView?

            do {
                let probe = GridProbeView(frame: CGRect(x: 10, y: 20, width: 100, height: 40))
                sut.addGridProbe(probe)
                sut.refreshOverlays()
                freed = probe
            }
            let actual = freed
            sut.isGridEnabled = false

            #expect(actual == nil)
        }

        @Test("A grid probe removed from its window is freed and no longer listed once its last owner lets go")
        func probeIsFreedAndUnlistedOnceRemoved() {
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 320, height: 200), styleMask: [.titled], backing: .buffered, defer: true)
            let content = NSView(frame: CGRect(x: 0, y: 0, width: 320, height: 200))
            window.contentView = content
            let sut = ViewBorderController(appWindows: { [window] })
            sut.isGridEnabled = true
            // 20 pt up from the bottom of a 200 pt view, 40 tall: 140 down from its top.
            let expectedListed = [CGRect(x: 10, y: 140, width: 100, height: 40)]
            let expectedAfter: [CGRect] = []
            var listed: [CGRect] = []
            weak var freed: GridProbeView?

            do {
                let probe = GridProbeView(frame: CGRect(x: 10, y: 20, width: 100, height: 40))
                autoreleasepool { content.addSubview(probe) }
                sut.addGridProbe(probe)
                sut.refreshOverlays()
                listed = sut.overlays.existing(over: window)?.model.grids ?? []
                autoreleasepool { probe.removeFromSuperview() }
                freed = probe
            }
            let actualFreed = freed
            sut.refreshOverlays()
            let actual = sut.overlays.existing(over: window)?.model.grids
            sut.isGridEnabled = false

            #expect(listed == expectedListed)
            #expect(actualFreed == nil)
            #expect(actual == expectedAfter)
        }
    }

// UIKit can't make a window in xctest, which runs package tests on Mac Catalyst without an
// NSApplication, so the iOS tests run on the iOS simulator alone.
#elseif os(iOS) && DEBUG && !targetEnvironment(macCatalyst)
    @testable import DebugDrawerViewInspectorPlugin
    import Testing
    import UIKit

    // The controller lists probes only for windows in a scene; Bazel's test host connects one,
    // SwiftPM's runner none, so there these tests don't run.
    @MainActor
    @Suite(.enabled("the test runner connects no window scene") { await hasWindowScene() })
    struct GridProbeLifetimeTests {
        @Test("A grid probe the controller added and listed is freed once its last owner lets go, with no autorelease pool drained")
        func probeIsFreedWithNoPool() throws {
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
            let sut = ViewBorderController(appWindows: { [window] })
            sut.isGridEnabled = true
            weak var freed: GridProbeView?

            do {
                let probe = GridProbeView(frame: CGRect(x: 10, y: 20, width: 100, height: 40))
                sut.addGridProbe(probe)
                sut.refreshOverlays()
                freed = probe
            }
            let actual = freed
            sut.isGridEnabled = false

            #expect(actual == nil)
        }

        @Test("A grid probe removed from its window is freed and no longer listed once its last owner lets go")
        func probeIsFreedAndUnlistedOnceRemoved() throws {
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 320, height: 200)
            let sut = ViewBorderController(appWindows: { [window] })
            sut.isGridEnabled = true
            let expectedListedCount = 1
            var listed: [CGRect] = []
            weak var freed: GridProbeView?

            do {
                let probe = GridProbeView(frame: CGRect(x: 10, y: 20, width: 100, height: 40))
                autoreleasepool { window.addSubview(probe) }
                sut.addGridProbe(probe)
                sut.refreshOverlays()
                listed = sut.overlays.existing(over: scene)?.model.grids ?? []
                autoreleasepool { probe.removeFromSuperview() }
                freed = probe
            }
            let actualFreed = freed
            sut.refreshOverlays()
            let actual = sut.overlays.existing(over: scene)?.model.grids ?? []
            sut.isGridEnabled = false

            #expect(listed.count == expectedListedCount)
            #expect(actualFreed == nil)
            #expect(actual.isEmpty)
        }
    }

    @MainActor
    private func hasWindowScene() -> Bool {
        UIApplication.shared.connectedScenes.contains { $0 is UIWindowScene }
    }
#endif
