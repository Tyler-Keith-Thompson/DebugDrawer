#if DEBUG
    import Combine
    @testable import DebugDrawer
    import Foundation
    import Testing
    #if os(macOS)
        import AppKit
    #endif
    // ViewInspector isn't linked on visionOS (APPLE_ONLY_PACKAGE_EXCLUDED_PLATFORMS in
    // scripts/modules.py).
    #if !os(visionOS)
        import ViewInspector
    #endif

    /// A scheduler whose clock moves only when the test advances it, running each action that
    /// comes due in time order. Hand-written: core's tests take no package for a clock.
    private final class TestScheduler: Scheduler {
        typealias SchedulerTimeType = DispatchQueue.SchedulerTimeType
        typealias SchedulerOptions = Never

        private struct Action {
            let id: Int
            let date: SchedulerTimeType
            let run: () -> Void
        }

        private struct Cancellation: Cancellable {
            let cancelAction: () -> Void
            func cancel() { cancelAction() }
        }

        // Not DispatchTime(uptimeNanoseconds: 0), which DispatchTime reads as "now".
        private(set) var now = SchedulerTimeType(DispatchTime(uptimeNanoseconds: 1))
        let minimumTolerance = SchedulerTimeType.Stride.zero
        private var actions: [Action] = []
        private var nextID = 0

        func schedule(options _: Never?, _ action: @escaping () -> Void) {
            enqueue(at: now, action)
        }

        func schedule(
            after date: SchedulerTimeType,
            tolerance _: SchedulerTimeType.Stride,
            options _: Never?,
            _ action: @escaping () -> Void
        ) {
            enqueue(at: date, action)
        }

        func schedule(
            after date: SchedulerTimeType,
            interval: SchedulerTimeType.Stride,
            tolerance _: SchedulerTimeType.Stride,
            options _: Never?,
            _ action: @escaping () -> Void
        ) -> any Cancellable {
            var isCancelled = false
            func repeatAt(_ date: SchedulerTimeType) {
                enqueue(at: date) {
                    guard !isCancelled else { return }
                    action()
                    repeatAt(date.advanced(by: interval))
                }
            }
            repeatAt(date)
            return Cancellation { isCancelled = true }
        }

        /// Moves the clock on by `stride`, running every action due by then, earliest first.
        func advance(by stride: SchedulerTimeType.Stride) {
            let end = now.advanced(by: stride)
            while let next = actions.filter({ $0.date <= end }).min(by: { ($0.date, $0.id) < ($1.date, $1.id) }) {
                actions.removeAll { $0.id == next.id }
                now = next.date
                next.run()
            }
            now = end
        }

        private func enqueue(at date: SchedulerTimeType, _ run: @escaping () -> Void) {
            actions.append(Action(id: nextID, date: date, run: run))
            nextID += 1
        }
    }

    @MainActor
    @Suite("Toast expiry")
    struct ToastExpiryTests {
        @Test("A toast goes away by itself six seconds after its post, and not before")
        func aToastExpires() throws {
            let suite = "ToastExpiryTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let scheduler = TestScheduler()
            let sut = DebugDrawer(defaults: defaults, toastScheduler: scheduler)
            let expected = DebugDrawerToast(pluginID: "Requests", message: "Request failed", count: 1)
            sut.postToast("Request failed", fromPlugin: "Requests")

            scheduler.advance(by: .milliseconds(5900))
            let beforeLifetime = sut.toast
            scheduler.advance(by: .milliseconds(100))

            #expect(DebugDrawer.toastLifetime == 6)
            #expect(beforeLifetime == expected)
            #expect(sut.toast == nil)
        }

        @Test("A new post to the toast starts its countdown again")
        func aPostRestartsTheCountdown() throws {
            let suite = "ToastExpiryTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let scheduler = TestScheduler()
            let sut = DebugDrawer(defaults: defaults, toastScheduler: scheduler)
            let expected = DebugDrawerToast(pluginID: "Requests", message: "Second failure", count: 2)
            sut.postToast("First failure", fromPlugin: "Requests")
            scheduler.advance(by: .seconds(4))

            sut.postToast("Second failure", fromPlugin: "Requests")
            scheduler.advance(by: .milliseconds(5900))
            let beforeLifetime = sut.toast
            scheduler.advance(by: .milliseconds(100))

            #expect(beforeLifetime == expected)
            #expect(sut.toast == nil)
        }

        @Test("A post from another plugin, replacing the toast, starts its countdown again")
        func anotherPluginsPostRestartsTheCountdown() throws {
            let suite = "ToastExpiryTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let scheduler = TestScheduler()
            let sut = DebugDrawer(defaults: defaults, toastScheduler: scheduler)
            let expected = DebugDrawerToast(pluginID: "Disk", message: "Write on main", count: 1)
            sut.postToast("Request failed", fromPlugin: "Requests")
            scheduler.advance(by: .seconds(5))

            sut.postToast("Write on main", fromPlugin: "Disk")
            scheduler.advance(by: .milliseconds(5900))
            let beforeLifetime = sut.toast
            scheduler.advance(by: .milliseconds(100))

            #expect(beforeLifetime == expected)
            #expect(sut.toast == nil)
        }

        @Test("A held toast stays, and goes six seconds after the hold ends", arguments: [DrawerToastHold.pointer, .accessibilityFocus])
        func aHeldToastStays(hold: DrawerToastHold) throws {
            let suite = "ToastExpiryTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let scheduler = TestScheduler()
            let sut = DebugDrawer(defaults: defaults, toastScheduler: scheduler)
            let expected = DebugDrawerToast(pluginID: "Requests", message: "Request failed", count: 1)
            sut.postToast("Request failed", fromPlugin: "Requests")
            scheduler.advance(by: .seconds(3))

            sut.setToastHeld(true, by: hold)
            scheduler.advance(by: .seconds(100))
            let whileHeld = sut.toast
            sut.setToastHeld(false, by: hold)
            scheduler.advance(by: .milliseconds(5900))
            let beforeLifetime = sut.toast
            scheduler.advance(by: .milliseconds(100))

            #expect(whileHeld == expected)
            #expect(beforeLifetime == expected)
            #expect(sut.toast == nil)
        }

        @Test("The toast stays until the last of two holds ends")
        func theLastHoldKeepsTheToast() throws {
            let suite = "ToastExpiryTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let scheduler = TestScheduler()
            let sut = DebugDrawer(defaults: defaults, toastScheduler: scheduler)
            let expected = DebugDrawerToast(pluginID: "Requests", message: "Request failed", count: 1)
            sut.postToast("Request failed", fromPlugin: "Requests")
            sut.setToastHeld(true, by: .pointer)
            sut.setToastHeld(true, by: .accessibilityFocus)

            sut.setToastHeld(false, by: .pointer)
            scheduler.advance(by: .seconds(100))
            let whileFocused = sut.toast
            sut.setToastHeld(false, by: .accessibilityFocus)
            scheduler.advance(by: .seconds(6))

            #expect(whileFocused == expected)
            #expect(sut.toast == nil)
        }

        @Test("Ending a hold that never started doesn't start the countdown again")
        func aStrayReleaseChangesNothing() throws {
            let suite = "ToastExpiryTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let scheduler = TestScheduler()
            let sut = DebugDrawer(defaults: defaults, toastScheduler: scheduler)
            sut.postToast("Request failed", fromPlugin: "Requests")
            scheduler.advance(by: .seconds(4))

            sut.setToastHeld(false, by: .pointer)
            scheduler.advance(by: .seconds(2))

            #expect(sut.toast == nil)
        }

        @Test("A toast dismissed and posted again gets a whole countdown of its own")
        func aDismissedToastPostedAgainLastsItsLifetime() throws {
            let suite = "ToastExpiryTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let scheduler = TestScheduler()
            let sut = DebugDrawer(defaults: defaults, toastScheduler: scheduler)
            let expected = DebugDrawerToast(pluginID: "Requests", message: "Again", count: 1)
            sut.postToast("Request failed", fromPlugin: "Requests")
            scheduler.advance(by: .seconds(5))
            sut.dismissToast()

            sut.postToast("Again", fromPlugin: "Requests")
            scheduler.advance(by: .milliseconds(5900))
            let beforeLifetime = sut.toast
            scheduler.advance(by: .milliseconds(100))

            #expect(beforeLifetime == expected)
            #expect(sut.toast == nil)
        }

        #if !os(visionOS)
            @Test("Accessibility focus on the toast's buttons holds it, and it goes six seconds after focus leaves")
            func accessibilityFocusHoldsTheToast() throws {
                let suite = "ToastExpiryTests.\(#function).\(UUID().uuidString)"
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let scheduler = TestScheduler()
                let drawer = DebugDrawer(defaults: defaults, toastScheduler: scheduler)
                let expected = DebugDrawerToast(pluginID: "Requests", message: "Request failed", count: 1)
                drawer.postToast("Request failed", fromPlugin: "Requests")
                let sut = try DrawerToastLayer(drawer: drawer).inspect().zStack()

                try sut.callOnChange(oldValue: DrawerToastView.FocusedButton?.none, newValue: .dismiss)
                scheduler.advance(by: .seconds(100))
                let whileFocused = drawer.toast
                try sut.callOnChange(oldValue: DrawerToastView.FocusedButton?.some(.dismiss), newValue: nil)
                scheduler.advance(by: .milliseconds(5900))
                let beforeLifetime = drawer.toast
                scheduler.advance(by: .milliseconds(100))

                #expect(whileFocused == expected)
                #expect(beforeLifetime == expected)
                #expect(drawer.toast == nil)
            }
        #endif

        #if os(macOS)
            // The toast's panel never becomes key (DrawerChromePanel), and AppKit sends a tracking
            // area's events in a window that isn't key only with `.activeAlways`: without it the
            // pointer couldn't hold the toast. SwiftUI makes the area for `onHover`; the panel is
            // never shown.
            @Test("On the Mac the toast's panel tracks the pointer while it isn't key")
            func thePanelTracksThePointer() throws {
                let suite = "ToastExpiryTests.\(#function).\(UUID().uuidString)"
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let drawer = DebugDrawer(defaults: defaults, toastScheduler: TestScheduler())
                drawer.postToast("Request failed", fromPlugin: "Requests")
                let window = NSWindow(
                    contentRect: NSRect(x: 0, y: 0, width: 480, height: 240),
                    styleMask: [.borderless],
                    backing: .buffered,
                    defer: false
                )
                let sut = DrawerChromePanel(role: .toast, host: window, drawer: drawer)
                defer { window.removeChildWindow(sut) }
                let hosting = try #require(sut.contentView?.subviews.first)
                hosting.layoutSubtreeIfNeeded()
                hosting.display()

                let actual = hosting.trackingAreas.map(\.options)

                #expect(!sut.isKeyWindow)
                #expect(actual.contains { $0.contains(.activeAlways) && $0.contains(.mouseEnteredAndExited) })
            }
        #endif
    }
#endif
