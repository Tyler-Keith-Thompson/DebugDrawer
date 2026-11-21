#if DEBUG
    @testable import DebugDrawer
    import Foundation
    import Testing

    /// What a plugin's installer keeps in a drawer: an object per type, made once.
    @MainActor
    private final class InstalledCounter {
        var count = 0
    }

    /// A second type, kept apart from ``InstalledCounter``.
    @MainActor
    private final class InstalledName {
        let name: String

        init(name: String) {
            self.name = name
        }
    }

    @MainActor
    @Suite("What plugins' installers keep in a drawer")
    struct DrawerInstallerStateTests {
        @Test("A drawer makes its object for a type once and hands the same one back, apart from another drawer's and another type's")
        func keptPerDrawerAndType() throws {
            let firstSuite = "DrawerInstallerStateTests.\(#function).first.\(UUID().uuidString)"
            let secondSuite = "DrawerInstallerStateTests.\(#function).second.\(UUID().uuidString)"
            defer {
                UserDefaults().removePersistentDomain(forName: firstSuite)
                UserDefaults().removePersistentDomain(forName: secondSuite)
            }
            let first = try DebugDrawer(defaults: #require(UserDefaults(suiteName: firstSuite)))
            let second = try DebugDrawer(defaults: #require(UserDefaults(suiteName: secondSuite)))
            var made = 0
            let expectedName = "first"

            let firstCounter = first.installerState { made += 1; return InstalledCounter() }
            firstCounter.count = 3
            let actual = first.installerState { made += 1; return InstalledCounter() }
            let secondCounter = second.installerState { made += 1; return InstalledCounter() }
            let name = first.installerState { InstalledName(name: expectedName) }

            #expect(actual === firstCounter)
            #expect(actual.count == 3)
            #expect(secondCounter !== firstCounter)
            #expect(secondCounter.count == 0)
            #expect(made == 2)
            #expect(name.name == expectedName)
        }

        @Test("A drawer lets go of what it kept as it goes")
        func releasedWithTheDrawer() throws {
            let suite = "DrawerInstallerStateTests.\(#function).\(UUID().uuidString)"
            defer { UserDefaults().removePersistentDomain(forName: suite) }
            weak var kept: InstalledCounter?

            do {
                let drawer = try DebugDrawer(defaults: #require(UserDefaults(suiteName: suite)))
                kept = drawer.installerState { InstalledCounter() }
                #expect(kept != nil)
            }

            #expect(kept == nil)
        }
    }
#endif
