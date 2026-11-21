#if DEBUG
    #if os(macOS)
        import AppKit
    #endif
    import Combine
    @testable import DebugDrawer
    import Foundation
    import Testing

    // A drawer made with DebugDrawer(defaults:) is told when its own window's drawer opens or
    // closes, and the shared drawer is told nothing. Each test is synchronous on the main actor,
    // so no other suite's work on the shared drawer runs between its steps.
    @MainActor
    @Suite("A drawer of its own opens and closes apart from the shared one")
    struct DrawerOwnPresentationTests {
        @Test("Toggling a drawer of its own opens and closes it, and the shared drawer neither changes nor publishes")
        func toggleOwnDrawer() throws {
            let suite = "DrawerOwnPresentationTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            let shared = DebugDrawer.shared
            let expectedSharedIsOpen = shared.isOpen
            var sharedChanges = 0
            let subscription = shared.objectWillChange.sink { sharedChanges += 1 }
            #expect(!sut.isOpen)

            sut.toggle()
            let openedIsOpen = sut.isOpen
            let openedSharedIsOpen = shared.isOpen
            sut.toggle()
            let closedIsOpen = sut.isOpen
            let closedSharedIsOpen = shared.isOpen

            subscription.cancel()
            #expect(openedIsOpen)
            #expect(!closedIsOpen)
            #expect(openedSharedIsOpen == expectedSharedIsOpen)
            #expect(closedSharedIsOpen == expectedSharedIsOpen)
            #expect(sharedChanges == 0)
        }

        @Test("Opening and closing a drawer of its own publish each change through its $isOpen, and repeating either publishes nothing more")
        func openAndCloseOwnDrawer() throws {
            let suite = "DrawerOwnPresentationTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            let shared = DebugDrawer.shared
            let expectedSharedIsOpen = shared.isOpen
            var sharedChanges = 0
            let sharedSubscription = shared.objectWillChange.sink { sharedChanges += 1 }
            let expected: [Bool] = [true, false]
            var actual: [Bool] = []
            let subscription = sut.$isOpen.dropFirst().sink { actual.append($0) }

            sut.open()
            let openedIsOpen = sut.isOpen
            sut.open()
            let reopenedIsOpen = sut.isOpen
            sut.close()
            let closedIsOpen = sut.isOpen
            sut.close()
            let reclosedIsOpen = sut.isOpen

            subscription.cancel()
            sharedSubscription.cancel()
            #expect(openedIsOpen)
            #expect(reopenedIsOpen)
            #expect(!closedIsOpen)
            #expect(!reclosedIsOpen)
            #expect(actual == expected)
            #expect(shared.isOpen == expectedSharedIsOpen)
            #expect(sharedChanges == 0)
        }

        #if os(macOS)
            @Test("toggle(in:) on a drawer of its own opens and closes that window's drawer and updates its isOpen, not the shared drawer's")
            func toggleInWindowOnOwnDrawer() throws {
                let suite = "DrawerOwnPresentationTests.\(#function).\(UUID().uuidString)"
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                // Borderless, far off screen and never ordered in: a real window that is never
                // seen and never takes focus, so the drawer's panel stays out too.
                let window = NSWindow(
                    contentRect: CGRect(x: -30000, y: -30000, width: 900, height: 600),
                    styleMask: .borderless, backing: .buffered, defer: false
                )
                window.isReleasedWhenClosed = false
                defer { window.close() }
                let sut = DebugDrawer(defaults: defaults)
                let shared = DebugDrawer.shared
                let expectedSharedIsOpen = shared.isOpen
                var sharedChanges = 0
                let subscription = shared.objectWillChange.sink { sharedChanges += 1 }

                sut.toggle(in: window)
                let attachment = try #require(sut.attachments.first { $0.window === window })
                let openedIsOpen = sut.isOpen
                let openedPresentation = attachment.presentation.isOpen
                sut.toggle(in: window)
                let closedIsOpen = sut.isOpen
                let closedPresentation = attachment.presentation.isOpen

                subscription.cancel()
                #expect(openedPresentation)
                #expect(openedIsOpen)
                #expect(!closedPresentation)
                #expect(!closedIsOpen)
                #expect(shared.isOpen == expectedSharedIsOpen)
                #expect(sharedChanges == 0)
            }
        #endif
    }
#endif
