#if DEBUG
    @testable import DebugDrawer
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

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

        @Test("The HUD lists registered pinned plugins that offer a HUD, in pin order, and nothing else")
        func theHUDListsPinnedReadouts() {
            let sut = DebugDrawer.shared
            sut.registerGlobal(ReadoutPlugin())
            sut.registerGlobal(ReadoutPlugin(id: "SecondReadout", title: "Second"))
            sut.registerGlobal(PlainPlugin())
            sut.toggleHUD(forPlugin: "SecondReadout")
            sut.toggleHUD(forPlugin: "PlainPlugin")
            sut.toggleHUD(forPlugin: "Unregistered")
            sut.toggleHUD(forPlugin: "ReadoutPlugin")
            defer {
                for id in ["SecondReadout", "PlainPlugin", "Unregistered", "ReadoutPlugin"] {
                    sut.toggleHUD(forPlugin: id)
                }
                for id in ["ReadoutPlugin", "SecondReadout", "PlainPlugin"] {
                    sut.unregisterGlobal(id: id)
                }
            }
            let expected = ["SecondReadout", "ReadoutPlugin"]

            let actual = sut.hudPlugins.map(\.id)

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

        @Test("Running an action while hidden hides the HUD during it and shows it after, even with the drawer kept")
        func theHUDIsHiddenWhileAnActionRuns() async {
            let sut = DebugDrawer.shared
            sut.registerGlobal(ReadoutPlugin())
            sut.toggleHUD(forPlugin: "ReadoutPlugin")
            defer {
                sut.toggleHUD(forPlugin: "ReadoutPlugin")
                sut.unregisterGlobal(id: "ReadoutPlugin")
            }

            let hiddenDuringAction = await withCheckedContinuation { continuation in
                sut.performWhileHidden(drawer: false) {
                    continuation.resume(returning: sut.isHUDHidden)
                }
            }

            #expect(hiddenDuringAction)
        }

        @Test("While an action runs hidden, the app's drawer modifier draws the HUD fully transparent, so a capture leaves it out")
        func theModifierDrawsNoHUDWhileHidden() async throws {
            let sut = DebugDrawer.shared
            sut.registerGlobal(ReadoutPlugin())
            sut.toggleHUD(forPlugin: "ReadoutPlugin")
            defer {
                sut.toggleHUD(forPlugin: "ReadoutPlugin")
                sut.unregisterGlobal(id: "ReadoutPlugin")
            }
            let app = Text("App").debugDrawer()
            let shownOpacity = try app.inspect().find(DrawerHUDView.self).opacity()

            let hiddenOpacity = await withCheckedContinuation { continuation in
                sut.performWhileHidden(drawer: false) {
                    continuation.resume(returning: try? app.inspect().find(DrawerHUDView.self).opacity())
                }
            }

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
    }
#endif
