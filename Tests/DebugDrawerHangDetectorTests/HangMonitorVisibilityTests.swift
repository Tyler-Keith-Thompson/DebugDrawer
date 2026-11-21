// What the monitor counts as the app goes out of sight and back (DD-173). The watched thread is a
// helper thread's run loop (SteppingThread), since a test runner's main thread doesn't turn its run
// loop, and the app's lifecycle is UIKit's notifications, by their names, posted on a center of the
// test's own from the watched thread, as the system posts them from the main thread's own work.
// A second monitor of the same run loop, which follows no lifecycle, is the control: its sampler
// ends each stall once it has captured it, so every stall is a hang it reports, and the monitor
// under test must report only those in sight.
#if DEBUG
    import CoreFoundation
    import DebugDrawerHangDetector
    import Foundation
    import os
    import Testing

    #if os(macOS)
        import AppKit
    #elseif canImport(UIKit)
        import UIKit
    #endif

    @Suite(.timeLimit(.minutes(1)))
    struct HangMonitorVisibilityTests {
        @Test("A stall begun after the app resigns active isn't reported")
        func afterResigningActive() throws {
            let center = NotificationCenter()
            let visibility = AppVisibility(
                center: center,
                hiding: [
                    Notification.Name("UIApplicationWillResignActiveNotification"),
                    Notification.Name("UIApplicationDidEnterBackgroundNotification"),
                    Notification.Name("UIApplicationWillEnterForegroundNotification")
                ],
                showing: [Notification.Name("UIApplicationDidBecomeActiveNotification")]
            )
            let release = DispatchSemaphore(value: 0)
            let reported = OSAllocatedUnfairLock<[DetectedHang]>(initialState: [])
            let controlReported = OSAllocatedUnfairLock<[DetectedHang]>(initialState: [])
            let thread = SteppingThread(steps: [
                { center.post(name: Notification.Name("UIApplicationWillResignActiveNotification"), object: nil) },
                { _ = release.wait(timeout: .now() + 30) }
            ])
            let control = HangMonitor(
                runLoop: thread.runLoop, sampler: ReleasingSampler(base: thread.sampler, release: release), threshold: .milliseconds(50),
                visibility: AppVisibility(center: NotificationCenter(), hiding: [], showing: [])
            ) { hang in controlReported.withLock { $0.append(hang) } }
            let sut = HangMonitor(
                runLoop: thread.runLoop, sampler: thread.sampler, threshold: .milliseconds(50), visibility: visibility
            ) { hang in reported.withLock { $0.append(hang) } }

            thread.run()
            let finished = thread.finished()
            let actual = reported.withLock { $0 }

            #expect(finished)
            #expect(controlReported.withLock { $0.count } == 1)
            #expect(actual.isEmpty)
            withExtendedLifetime((sut, control)) {}
        }

        @Test("A stall while the app is in the background, or coming back to the foreground, isn't reported")
        func inBackground() throws {
            let center = NotificationCenter()
            let visibility = AppVisibility(
                center: center,
                hiding: [
                    Notification.Name("UIApplicationWillResignActiveNotification"),
                    Notification.Name("UIApplicationDidEnterBackgroundNotification"),
                    Notification.Name("UIApplicationWillEnterForegroundNotification")
                ],
                showing: [Notification.Name("UIApplicationDidBecomeActiveNotification")]
            )
            let release = DispatchSemaphore(value: 0)
            let reported = OSAllocatedUnfairLock<[DetectedHang]>(initialState: [])
            let controlReported = OSAllocatedUnfairLock<[DetectedHang]>(initialState: [])
            // The background's stall is the snapshot's: posted between entering the background and
            // the foreground, as the system takes it after the app's background handler returns.
            let thread = SteppingThread(steps: [
                { center.post(name: Notification.Name("UIApplicationWillResignActiveNotification"), object: nil) },
                { center.post(name: Notification.Name("UIApplicationDidEnterBackgroundNotification"), object: nil) },
                { _ = release.wait(timeout: .now() + 30) },
                { center.post(name: Notification.Name("UIApplicationWillEnterForegroundNotification"), object: nil) },
                { _ = release.wait(timeout: .now() + 30) }
            ])
            let control = HangMonitor(
                runLoop: thread.runLoop, sampler: ReleasingSampler(base: thread.sampler, release: release), threshold: .milliseconds(50),
                visibility: AppVisibility(center: NotificationCenter(), hiding: [], showing: [])
            ) { hang in controlReported.withLock { $0.append(hang) } }
            let sut = HangMonitor(
                runLoop: thread.runLoop, sampler: thread.sampler, threshold: .milliseconds(50), visibility: visibility
            ) { hang in reported.withLock { $0.append(hang) } }

            thread.run()
            let finished = thread.finished()
            let actual = reported.withLock { $0 }

            #expect(finished)
            #expect(controlReported.withLock { $0.count } == 2)
            #expect(actual.isEmpty)
            withExtendedLifetime((sut, control)) {}
        }

        @Test("A stall the app resigns active in isn't reported, though it began while active and its stack was captured")
        func spanningResignActive() throws {
            let center = NotificationCenter()
            let visibility = AppVisibility(
                center: center,
                hiding: [
                    Notification.Name("UIApplicationWillResignActiveNotification"),
                    Notification.Name("UIApplicationDidEnterBackgroundNotification"),
                    Notification.Name("UIApplicationWillEnterForegroundNotification")
                ],
                showing: [Notification.Name("UIApplicationDidBecomeActiveNotification")]
            )
            let release = DispatchSemaphore(value: 0)
            let reported = OSAllocatedUnfairLock<[DetectedHang]>(initialState: [])
            let controlReported = OSAllocatedUnfairLock<[DetectedHang]>(initialState: [])
            // The monitor under test samples too, and so releases the stall: it captured the stack
            // before the app resigned active.
            let thread = SteppingThread(steps: [
                {
                    _ = release.wait(timeout: .now() + 30)
                    _ = release.wait(timeout: .now() + 30)
                    center.post(name: Notification.Name("UIApplicationWillResignActiveNotification"), object: nil)
                }
            ])
            let control = HangMonitor(
                runLoop: thread.runLoop, sampler: ReleasingSampler(base: thread.sampler, release: release), threshold: .milliseconds(50),
                visibility: AppVisibility(center: NotificationCenter(), hiding: [], showing: [])
            ) { hang in controlReported.withLock { $0.append(hang) } }
            let sut = HangMonitor(
                runLoop: thread.runLoop, sampler: ReleasingSampler(base: thread.sampler, release: release), threshold: .milliseconds(50),
                visibility: visibility
            ) { hang in reported.withLock { $0.append(hang) } }

            thread.run()
            let finished = thread.finished()
            let actual = reported.withLock { $0 }

            #expect(finished)
            #expect(controlReported.withLock { $0.count } == 1)
            #expect(try #require(controlReported.withLock { $0.first }).addresses.isEmpty == false)
            #expect(actual.isEmpty)
            withExtendedLifetime((sut, control)) {}
        }

        @Test("A stall in the app's own code once it is active again is reported with its stack")
        func activeAgain() throws {
            let center = NotificationCenter()
            let visibility = AppVisibility(
                center: center,
                hiding: [
                    Notification.Name("UIApplicationWillResignActiveNotification"),
                    Notification.Name("UIApplicationDidEnterBackgroundNotification"),
                    Notification.Name("UIApplicationWillEnterForegroundNotification")
                ],
                showing: [Notification.Name("UIApplicationDidBecomeActiveNotification")]
            )
            let release = DispatchSemaphore(value: 0)
            let reported = OSAllocatedUnfairLock<[DetectedHang]>(initialState: [])
            let thread = SteppingThread(steps: [
                { center.post(name: Notification.Name("UIApplicationWillResignActiveNotification"), object: nil) },
                { center.post(name: Notification.Name("UIApplicationDidEnterBackgroundNotification"), object: nil) },
                { center.post(name: Notification.Name("UIApplicationWillEnterForegroundNotification"), object: nil) },
                { center.post(name: Notification.Name("UIApplicationDidBecomeActiveNotification"), object: nil) },
                { _ = release.wait(timeout: .now() + 30) }
            ])
            let sut = HangMonitor(
                runLoop: thread.runLoop, sampler: ReleasingSampler(base: thread.sampler, release: release), threshold: .milliseconds(50),
                visibility: visibility
            ) { hang in reported.withLock { $0.append(hang) } }

            thread.run()
            let finished = thread.finished()
            let actual = reported.withLock { $0 }
            let frames = Symbolicator.lines(for: try #require(actual.first).addresses)

            #expect(finished)
            #expect(actual.count == 1)
            #expect(try #require(actual.first).duration >= .milliseconds(50))
            #expect(frames.contains { $0.contains("dispatch_semaphore_wait") || $0.contains("DispatchSemaphore") })
            #expect(frames.contains { $0.contains("CFRunLoop") })
            withExtendedLifetime(sut) {}
        }

        @Test("A stall in the pass the app becomes active in, after it, is reported, counted from becoming active")
        func inBecomingActivePass() throws {
            let center = NotificationCenter()
            let visibility = AppVisibility(
                center: center,
                hiding: [
                    Notification.Name("UIApplicationWillResignActiveNotification"),
                    Notification.Name("UIApplicationDidEnterBackgroundNotification"),
                    Notification.Name("UIApplicationWillEnterForegroundNotification")
                ],
                showing: [Notification.Name("UIApplicationDidBecomeActiveNotification")]
            )
            let release = DispatchSemaphore(value: 0)
            let reported = OSAllocatedUnfairLock<[DetectedHang]>(initialState: [])
            // The stall stands for the app's own handler of becoming active, which the system
            // calls in the same pass, after the post.
            let thread = SteppingThread(steps: [
                { center.post(name: Notification.Name("UIApplicationWillResignActiveNotification"), object: nil) },
                {
                    center.post(name: Notification.Name("UIApplicationDidBecomeActiveNotification"), object: nil)
                    _ = release.wait(timeout: .now() + 30)
                }
            ])
            let sut = HangMonitor(
                runLoop: thread.runLoop, sampler: ReleasingSampler(base: thread.sampler, release: release), threshold: .milliseconds(50),
                visibility: visibility
            ) { hang in reported.withLock { $0.append(hang) } }

            thread.run()
            let finished = thread.finished()
            let actual = reported.withLock { $0 }
            let frames = Symbolicator.lines(for: try #require(actual.first).addresses)

            #expect(finished)
            #expect(actual.count == 1)
            #expect(frames.contains { $0.contains("dispatch_semaphore_wait") || $0.contains("DispatchSemaphore") })
            withExtendedLifetime(sut) {}
        }

        #if os(macOS)
            @Test("On the Mac the app is out of sight only while hidden: resigning active pauses nothing")
            func macLifecycle() {
                let expected = AppVisibility(
                    center: .default, hiding: [NSApplication.willHideNotification], showing: [NSApplication.didUnhideNotification]
                )

                let actual = AppVisibility.system

                #expect(actual.center === expected.center)
                #expect(actual.hiding == expected.hiding)
                #expect(actual.showing == expected.showing)
            }
        #elseif targetEnvironment(macCatalyst)
            @Test("In a Catalyst app the app is out of sight only in the background: an inactive window is still on screen")
            func catalystLifecycle() {
                let expectedHiding = [UIApplication.didEnterBackgroundNotification]
                let expectedShowing = [UIApplication.willEnterForegroundNotification, UIApplication.didBecomeActiveNotification]

                let actual = AppVisibility.system

                #expect(actual.center === NotificationCenter.default)
                #expect(actual.hiding == expectedHiding)
                #expect(actual.showing == expectedShowing)
            }
        #elseif canImport(UIKit)
            @Test("On iOS the app is out of sight from resigning active until it is active again, by UIKit's notifications")
            func uiKitLifecycle() {
                let expectedHiding = [
                    UIApplication.willResignActiveNotification, UIApplication.didEnterBackgroundNotification,
                    UIApplication.willEnterForegroundNotification
                ]
                let expectedShowing = [UIApplication.didBecomeActiveNotification]

                let actual = AppVisibility.system

                #expect(actual.center === NotificationCenter.default)
                #expect(actual.hiding == expectedHiding)
                #expect(actual.showing == expectedShowing)
                #expect(expectedHiding.map(\.rawValue) == [
                    "UIApplicationWillResignActiveNotification", "UIApplicationDidEnterBackgroundNotification",
                    "UIApplicationWillEnterForegroundNotification"
                ])
            }
        #endif
    }
#endif
