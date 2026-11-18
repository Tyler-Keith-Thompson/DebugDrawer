// The click indicators' UIWindow.sendEvent(_:) swizzle, which only iOS has. A swizzle is
// process-wide, so these tests sit in a serialized suite and file of their own. They are plain
// tests rather than exit tests, which an iOS simulator can't run: installViewInspector() swaps
// once and never back, and the swapped-in method forwards every event unchanged and draws only
// while click indicators are on, so leaving it installed changes nothing another test sees. A test
// that turns click indicators on turns them off again in the same main-actor turn, so no other
// test sees them on.
#if os(iOS) && DEBUG
    @testable import DebugDrawer
    @testable import DebugDrawerViewInspectorPlugin
    import Darwin
    import ObjectiveC
    import Testing
    import UIKit

    /// A window that records what the swapped-in sendEvent(_:) forwards instead of handing the
    /// fake event to UIKit: after the swap, dd_sendEvent(_:) names UIKit's original.
    private final class ForwardingProbeWindow: UIWindow {
        var forwarded: [UIEvent] = []

        override func dd_sendEvent(_ event: UIEvent) {
            forwarded.append(event)
        }
    }

    /// A touch that has just begun, at a fixed point.
    private final class BeganTouch: UITouch {
        override var phase: UITouch.Phase { .began }

        override func location(in view: UIView?) -> CGPoint { CGPoint(x: 40, y: 40) }
    }

    /// An event carrying one touch that has just begun.
    private final class BeganTouchEvent: UIEvent {
        let touch = BeganTouch()

        override var allTouches: Set<UITouch>? { [touch] }
    }

    @MainActor
    @Suite(.serialized)
    struct ClickIndicatorSwizzleTests {
        @Test("installViewInspector() swaps in dd_sendEvent(_:) once; a second call or the switch swaps nothing")
        func installSwizzlesOnce() throws {
            let sendEvent = try #require(class_getInstanceMethod(UIWindow.self, #selector(UIWindow.sendEvent(_:))))
            let ddSendEvent = try #require(class_getInstanceMethod(UIWindow.self, #selector(UIWindow.dd_sendEvent(_:))))
            let controller = ViewBorderController.shared
            DebugDrawer.shared.installViewInspector()
            let installed = method_getImplementation(sendEvent)
            let original = method_getImplementation(ddSendEvent)
            // dd_sendEvent(_:)'s body is the plugin's code, while UIKit's sendEvent(_:) is
            // UIKitCore's, so the image an implementation lives in says which one it is, whether
            // or not an earlier test installed the swizzle first.
            var pluginImage = Dl_info()
            var installedImage = Dl_info()
            var originalImage = Dl_info()
            dladdr(unsafeBitCast(ViewBorderController.self, to: UnsafeRawPointer.self), &pluginImage)
            dladdr(UnsafeRawPointer(installed), &installedImage)
            dladdr(UnsafeRawPointer(original), &originalImage)

            DebugDrawer.shared.installViewInspector()
            let afterSecondInstall = method_getImplementation(sendEvent)
            controller.isClickIndicatorEnabled = true
            let afterTurningOn = method_getImplementation(sendEvent)
            controller.isClickIndicatorEnabled = false
            let actual = method_getImplementation(sendEvent)

            #expect(installedImage.dli_fbase == pluginImage.dli_fbase)
            #expect(originalImage.dli_fbase != pluginImage.dli_fbase)
            #expect(afterSecondInstall == installed)
            #expect(afterTurningOn == installed)
            #expect(actual == installed)
            #expect(method_getImplementation(ddSendEvent) == original)
        }

        @Test("With click indicators off, the swapped-in sendEvent(_:) forwards the event once and draws nothing")
        func indicatorsOffForwardAndDrawNothing() {
            DebugDrawer.shared.installViewInspector()
            ViewBorderController.shared.isClickIndicatorEnabled = false
            let sut = ForwardingProbeWindow()
            let event = BeganTouchEvent()

            sut.sendEvent(event)

            #expect(sut.forwarded.count == 1)
            #expect(sut.forwarded.first === event)
            #expect(sut.subviews.isEmpty)
        }

        @Test("With click indicators on, the swapped-in sendEvent(_:) forwards the event once and draws a ripple for the touch that began")
        func indicatorsOnForwardAndDrawARipple() {
            DebugDrawer.shared.installViewInspector()
            let controller = ViewBorderController.shared
            let sut = ForwardingProbeWindow()
            let event = BeganTouchEvent()
            let expectedRipples = 1

            controller.isClickIndicatorEnabled = true
            sut.sendEvent(event)
            controller.isClickIndicatorEnabled = false

            #expect(sut.forwarded.count == 1)
            #expect(sut.forwarded.first === event)
            #expect(sut.subviews.count == expectedRipples)
        }
    }
#endif
