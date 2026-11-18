// The views are hosted on the Mac and, through `just test-ios`, in the iOS simulator.
#if os(macOS)
    import AppKit
    @testable import DebugDrawerDesignOverlayPlugin
    import SwiftUI
    import Testing

    /// The app's content in the tests: a platform view a hit test can name.
    private struct ContentProbe: NSViewRepresentable {
        func makeNSView(context _: Context) -> ContentProbeView {
            ContentProbeView()
        }

        func updateNSView(_: ContentProbeView, context _: Context) {}
    }

    private final class ContentProbeView: NSView {}

    @MainActor
    @Suite("Design overlay hit testing")
    struct DesignOverlayHitTestingTests {
        @Test("With the mockup shown over the whole window and Move off, a click on it reaches the app's view beneath")
        func clickPassesThrough() throws {
            let model = DesignOverlayModel(storage: FakeMockupStorage())
            // 1600 by 1200 pixels at @2x covers the 800 by 600 point window.
            model.open(MockupFixture.png(width: 1600, height: 1200))
            model.settings.opacity = 1
            let host = NSHostingView(rootView: ContentProbe().frame(width: 800, height: 600).modifier(DesignOverlayModifier(model: model)))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            host.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
            host.layoutSubtreeIfNeeded()
            let overMockup = CGPoint(x: 400, y: 300)

            let actual = host.hitTest(overMockup)

            #expect(model.mockup != nil && model.settings.isVisible)
            #expect(actual is ContentProbeView)
        }

        @Test("While Move is on, the mockup takes the click instead, so a drag moves it")
        func moveTakesClicks() throws {
            let model = DesignOverlayModel(storage: FakeMockupStorage())
            model.open(MockupFixture.png(width: 1600, height: 1200))
            model.isMoving = true
            let host = NSHostingView(rootView: ContentProbe().frame(width: 800, height: 600).modifier(DesignOverlayModifier(model: model)))
            let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 800, height: 600), styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            host.frame = CGRect(x: 0, y: 0, width: 800, height: 600)
            host.layoutSubtreeIfNeeded()
            let overMockup = CGPoint(x: 400, y: 300)

            let actual = host.hitTest(overMockup)

            #expect(actual != nil)
            #expect(!(actual is ContentProbeView))
        }
    }
// UIKit can't make a window in xctest, which runs package tests on Mac Catalyst without an
// NSApplication, so the iOS tests run on the iOS simulator alone.
#elseif os(iOS) && !targetEnvironment(macCatalyst)
    @testable import DebugDrawerDesignOverlayPlugin
    import SwiftUI
    import Testing
    import UIKit

    /// The app's content in the tests: a platform view a hit test can name.
    private struct ContentProbe: UIViewRepresentable {
        func makeUIView(context _: Context) -> ContentProbeView {
            ContentProbeView()
        }

        func updateUIView(_: ContentProbeView, context _: Context) {}
    }

    private final class ContentProbeView: UIView {}

    @MainActor
    @Suite("Design overlay hit testing")
    struct DesignOverlayHitTestingTests {
        @Test("With the mockup shown over the whole window and Move off, a touch on it reaches the app's view beneath")
        func touchPassesThrough() throws {
            let model = DesignOverlayModel(storage: FakeMockupStorage())
            model.open(MockupFixture.png(width: 2048, height: 1536))
            model.settings.opacity = 1
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
            window.rootViewController = UIHostingController(rootView: ContentProbe().modifier(DesignOverlayModifier(model: model)))
            window.isHidden = false
            defer { window.isHidden = true }
            window.layoutIfNeeded()
            let overMockup = CGPoint(x: 512, y: 384)

            let actual = window.hitTest(overMockup, with: nil)

            #expect(actual is ContentProbeView)
        }

        @Test("While Move is on, the mockup takes the touch instead, so a drag moves it")
        func moveTakesTouches() throws {
            let model = DesignOverlayModel(storage: FakeMockupStorage())
            model.open(MockupFixture.png(width: 2048, height: 1536))
            model.isMoving = true
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 1024, height: 768))
            window.rootViewController = UIHostingController(rootView: ContentProbe().modifier(DesignOverlayModifier(model: model)))
            window.isHidden = false
            defer { window.isHidden = true }
            window.layoutIfNeeded()
            let overMockup = CGPoint(x: 512, y: 384)

            let actual = window.hitTest(overMockup, with: nil)

            #expect(actual != nil)
            #expect(!(actual is ContentProbeView))
        }
    }
#endif
