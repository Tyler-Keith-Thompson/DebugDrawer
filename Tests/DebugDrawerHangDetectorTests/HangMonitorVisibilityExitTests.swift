// The Mac's lifecycle as the shipped monitor follows it (AppVisibility.system): AppKit's own
// notifications, posted on the default center, which every monitor of the process follows, so this
// runs in a child process, in a file of its own, as exit tests need one. The watched thread is a
// helper thread's run loop (SteppingThread); a second monitor that follows no lifecycle is the
// control, whose sampler ends each stall once it has captured it.
#if os(macOS) && DEBUG
    import AppKit
    import CoreFoundation
    import DebugDrawerHangDetector
    import Foundation
    import os
    import Testing

    @Suite("Hang monitor visibility, in a child process", .timeLimit(.minutes(1)))
    struct HangMonitorVisibilityExitTests {
        @Test("On the Mac a stall while the app is inactive is reported, one while it is hidden isn't, and one once unhidden is")
        func macLifecycle() async {
            // The children get a home folder of their own, so what they keep there (Application Support,
            // Caches, preferences) stays out of the Mac's, whatever runs the test; each checks it took.
            let home = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).path(percentEncoded: false)
            defer { try? FileManager.default.removeItem(atPath: home) }

            await #expect(processExitsWith: .success) { [home = home as String] in
                setenv("CFFIXED_USER_HOME", home, 1)
                guard URL.applicationSupportDirectory.path(percentEncoded: false).hasPrefix(home) else { exit(EXIT_FAILURE) }
                let release = DispatchSemaphore(value: 0)
                let reported = OSAllocatedUnfairLock<[DetectedHang]>(initialState: [])
                let controlReported = OSAllocatedUnfairLock<[DetectedHang]>(initialState: [])
                let thread = SteppingThread(steps: [
                    { NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: nil) },
                    { _ = release.wait(timeout: .now() + 30) },
                    { NotificationCenter.default.post(name: NSApplication.willHideNotification, object: nil) },
                    { _ = release.wait(timeout: .now() + 30) },
                    { NotificationCenter.default.post(name: NSApplication.didUnhideNotification, object: nil) },
                    { _ = release.wait(timeout: .now() + 30) }
                ])
                let control = HangMonitor(
                    runLoop: thread.runLoop, sampler: ReleasingSampler(base: thread.sampler, release: release), threshold: .milliseconds(50),
                    visibility: AppVisibility(center: NotificationCenter(), hiding: [], showing: [])
                ) { hang in controlReported.withLock { $0.append(hang) } }
                let sut = HangMonitor(runLoop: thread.runLoop, sampler: thread.sampler, threshold: .milliseconds(50)) { hang in
                    reported.withLock { $0.append(hang) }
                }

                thread.run()
                let finished = thread.finished()
                sut.stop()
                control.stop()

                let isExpected = finished && controlReported.withLock { $0.count } == 3 && reported.withLock { $0.count } == 2
                exit(isExpected ? EXIT_SUCCESS : EXIT_FAILURE)
            }
        }
    }
#endif
