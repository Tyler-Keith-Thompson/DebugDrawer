#if DEBUG
    @testable import DebugDrawer
    import Foundation
    import SwiftUI
    import Testing

    // ViewInspector isn't linked on visionOS (APPLE_ONLY_PACKAGE_EXCLUDED_PLATFORMS in
    // scripts/modules.py), so the tests that inspect views run everywhere else.
    #if !os(visionOS)
        import ViewInspector
    #endif

    struct ReadoutPlugin: DebugDrawerPlugin {
        var id = "ReadoutPlugin"
        var title = "Readout"
        var icon = "gauge"
        var body: some View { EmptyView() }
        var hud: Text? { Text("42 FPS") }
    }

    struct PlainPlugin: DebugDrawerPlugin {
        var title = "Plain"
        var icon = "square"
        var body: some View { EmptyView() }
    }

    @Suite("HUD layout")
    struct HUDLayoutTests {
        @Test("Pinning appends in order and pinning again removes")
        func pinningTogglesInOrder() {
            var sut = HUDLayout()
            let expected = ["B"]

            sut.togglePin("A")
            sut.togglePin("B")
            sut.togglePin("A")

            #expect(sut.pinned == expected)
        }

        @Test("The pins and the position survive a save and a load")
        func pinsAndPositionPersist() throws {
            let suite = "HUDLayoutTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            var expected = HUDLayout()
            expected.togglePin("PerformancePlugin")
            expected.togglePin("EnergyPlugin")
            expected.origin = CGPoint(x: 240, y: 96)

            expected.save(to: defaults)
            let actual = HUDLayout(from: defaults)

            #expect(actual == expected)
        }

        @Test("Unreadable saved data loads as an empty layout at the default corner")
        func garbageLoadsEmpty() throws {
            let suite = "HUDLayoutTests.\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(Data("not json".utf8), forKey: HUDLayout.defaultsKey)

            let actual = HUDLayout(from: defaults)

            #expect(actual == HUDLayout())
            #expect(actual.origin == nil)
        }
    }

    // Serialized: these tests change the one shared drawer.
    @MainActor
    @Suite("HUD", .serialized, .timeLimit(.minutes(1)))
    struct HUDTests {
        @Test("A plugin that declares no HUD offers none; one that declares a HUD offers it")
        func pluginsOfferAHUDOnlyWhenTheyDeclareOne() {
            let plain = AnyDebugDrawerPlugin(PlainPlugin())
            let readout = AnyDebugDrawerPlugin(ReadoutPlugin())

            #expect(!plain.hasHUD)
            #expect(plain.hud == nil)
            #expect(readout.hasHUD)
            #expect(readout.hud != nil)
        }

        // Synchronous, so registering, checking and unregistering happen in one main-actor turn and
        // suites that check the shared drawer's registry never see these plugins. Pins are set in
        // memory, not toggled, so a pin saved by another run can't invert the result.
        @Test("The HUD lists registered pinned plugins that offer a HUD, in pin order, and nothing else")
        func theHUDListsPinnedReadouts() {
            let sut = DebugDrawer.shared
            let previous = sut.hudLayout
            sut.registerGlobal(ReadoutPlugin())
            sut.registerGlobal(ReadoutPlugin(id: "SecondReadout", title: "Second"))
            sut.registerGlobal(PlainPlugin())
            sut.hudLayout.pinned = ["SecondReadout", "PlainPlugin", "Unregistered", "ReadoutPlugin"]
            let expected = ["SecondReadout", "ReadoutPlugin"]

            let actual = sut.hudPlugins.map(\.id)

            sut.hudLayout = previous
            for id in ["ReadoutPlugin", "SecondReadout", "PlainPlugin"] {
                sut.unregisterGlobal(id: id)
            }
            #expect(actual == expected)
        }

        @Test("Moving the HUD saves its corner")
        func movingTheHUDSavesItsCorner() {
            let sut = DebugDrawer.shared
            let previous = sut.hudLayout.origin
            defer {
                sut.moveHUD(to: previous ?? DrawerHUDView.defaultOrigin)
            }
            let expected = CGPoint(x: 300, y: 40)

            sut.moveHUD(to: expected)

            #expect(sut.hudLayout.origin == expected)
            #expect(HUDLayout(from: .standard).origin == expected)
        }

        @Test("Running an action while hidden hides the HUD during it, even with the drawer kept")
        func theHUDIsHiddenWhileAnActionRuns() async {
            let sut = DebugDrawer.shared
            let previous = sut.hudLayout
            // A pin in memory is all hiding needs; no plugin is registered across the await.
            sut.hudLayout.pinned = ["ReadoutPlugin"]
            defer { sut.hudLayout = previous }

            let hiddenDuringAction = await withCheckedContinuation { continuation in
                sut.performWhileHidden(drawer: false) {
                    continuation.resume(returning: sut.isHUDHidden)
                }
            }

            #expect(hiddenDuringAction)
        }

        #if !os(visionOS)
            // Synchronous for the same reason as the HUD list test.
            @Test("While the HUD is hidden, the app's drawer modifier draws it fully transparent, so a capture leaves it out")
            func theModifierDrawsNoHUDWhileHidden() {
                let sut = DebugDrawer.shared
                let previous = sut.hudLayout
                sut.registerGlobal(ReadoutPlugin())
                sut.hudLayout.pinned = ["ReadoutPlugin"]
                let app = Text("App").debugDrawer()

                let shownOpacity = try? app.inspect().find(DrawerHUDView.self).opacity()
                sut.isHUDHidden = true
                let hiddenOpacity = try? app.inspect().find(DrawerHUDView.self).opacity()

                sut.isHUDHidden = false
                sut.hudLayout = previous
                sut.unregisterGlobal(id: "ReadoutPlugin")
                #expect(shownOpacity == 1)
                #expect(hiddenOpacity == 0)
            }

            @Test("The HUD card shows each pinned plugin's readout")
            func theCardShowsReadouts() throws {
                let sut = DrawerHUDView(
                    readouts: [AnyDebugDrawerPlugin(ReadoutPlugin())],
                    origin: nil,
                    move: { _ in },
                    unpin: { _ in }
                )

                let inspected = try sut.inspect()

                #expect(throws: Never.self) { try inspected.find(text: "42 FPS") }
            }
        #endif
    }
#endif
