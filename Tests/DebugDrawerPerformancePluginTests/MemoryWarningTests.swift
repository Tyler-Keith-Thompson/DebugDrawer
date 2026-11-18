// The memory warning exists on UIKit's platforms only, so these run on the iOS simulator
// (`just test-ios`), where the plugin's real poster posts to a notification center of the test's.
#if os(iOS)
    @testable import DebugDrawerPerformancePlugin
    import os
    import SwiftUI
    import Testing
    import UIKit
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct MemoryWarningTests {
        @Test("Tapping Simulate Memory Warning fires an observer of didReceiveMemoryWarningNotification, from the shared application")
        func tapNotifiesObservers() throws {
            let center = NotificationCenter()
            // The observer's block is Sendable; it runs on the posting thread, as `queue: nil` asks.
            let received = OSAllocatedUnfairLock<[ObjectIdentifier?]>(initialState: [])
            let observer = center.addObserver(forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: nil) { notification in
                let sender = (notification.object as AnyObject?).map(ObjectIdentifier.init)
                received.withLock { $0.append(sender) }
            }
            defer { center.removeObserver(observer) }
            let simulator = MemoryWarningSimulator(center: center)
            let sut = MemoryWarningSection { simulator.post() }

            try sut.inspect().find(button: "Simulate Memory Warning").tap()

            let actual = received.withLock { $0 }
            #expect(actual == [ObjectIdentifier(UIApplication.shared)])
        }

        // ViewHosting hosts the view in a window, which UIKit can't make in xctest, which runs
        // package tests on Mac Catalyst without an NSApplication.
        #if !targetEnvironment(macCatalyst)
            @Test("After a tap, the section keeps when the warning was posted and says so")
            func postedAt() async throws {
                let expected = Date(timeIntervalSince1970: 1_800_000_189)
                let sut = MemoryWarningSection { expected }
                var before: Date?
                var actual: Date?
                var texts: [String] = []

                try await ViewHosting.host(sut) {
                    try await sut.inspection.inspect { view in
                        before = try view.actualView().postedAt
                        try view.find(button: "Simulate Memory Warning").tap()
                    }
                    try await sut.inspection.inspect { view in
                        actual = try view.actualView().postedAt
                        texts = try view.findAll(ViewType.Text.self).map { try $0.string() }
                    }
                }

                #expect(before == nil)
                #expect(actual == expected)
                #expect(texts.contains { $0.hasPrefix("Posted at ") })
            }
        #endif

        @Test("The help text says only observers receive the warning, and claims nothing of view controllers or caches")
        func helpText() throws {
            let sut = MemoryWarningSection { Date() }

            let actual = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }.joined(separator: " ")

            #expect(actual.contains("Only the app's observers of it receive it."))
            #expect(!actual.contains("didReceiveMemoryWarning()"))
            #expect(!actual.contains("NSCache"))
        }
    }
#endif
