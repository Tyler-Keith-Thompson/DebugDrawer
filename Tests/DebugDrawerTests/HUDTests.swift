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
            let suite = "HUDLayoutTests.\(#function).\(UUID().uuidString)"
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
            let suite = "HUDLayoutTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(Data("not json".utf8), forKey: HUDLayout.defaultsKey)

            let actual = HUDLayout(from: defaults)

            #expect(actual == HUDLayout())
            #expect(actual.origin == nil)
        }
    }

    // Each test that needs a drawer makes one of its own over a UserDefaults suite named for the
    // test, removed when the test ends, so the pins and corner it saves reach no other test.
    @MainActor
    @Suite("HUD", .timeLimit(.minutes(1)))
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
        func theHUDListsPinnedReadouts() throws {
            let suite = "HUDTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            sut.registerGlobal(ReadoutPlugin())
            sut.registerGlobal(ReadoutPlugin(id: "SecondReadout", title: "Second"))
            sut.registerGlobal(PlainPlugin())
            sut.hudLayout.pinned = ["SecondReadout", "DebugDrawerTests.PlainPlugin", "Unregistered", "ReadoutPlugin"]
            let expected = ["SecondReadout", "ReadoutPlugin"]

            let actual = sut.hudPlugins.map(\.id)

            #expect(actual == expected)
        }

        @Test("Moving the HUD saves its corner")
        func movingTheHUDSavesItsCorner() throws {
            let suite = "HUDTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            let expected = CGPoint(x: 300, y: 40)

            sut.moveHUD(to: expected)

            #expect(sut.hudLayout.origin == expected)
            #expect(HUDLayout(from: sut.defaults).origin == expected)
        }

        @Test("Running an action while hidden hides the HUD during it, even with the drawer kept")
        func theHUDIsHiddenWhileAnActionRuns() async throws {
            let suite = "HUDTests.\(#function).\(UUID().uuidString)"
            let defaults = try #require(UserDefaults(suiteName: suite))
            defer { defaults.removePersistentDomain(forName: suite) }
            let sut = DebugDrawer(defaults: defaults)
            // A pin is all hiding needs; no plugin is registered.
            sut.hudLayout.pinned = ["ReadoutPlugin"]

            let hiddenDuringAction = await withCheckedContinuation { continuation in
                sut.performWhileHidden(drawer: false) {
                    continuation.resume(returning: sut.isHUDHidden)
                }
            }

            #expect(hiddenDuringAction)
        }

        #if !os(visionOS)
            @Test("While the HUD is hidden, its layer draws it fully transparent, so a capture leaves it out")
            func theLayerDrawsNoHUDWhileHidden() throws {
                let suite = "HUDTests.\(#function).\(UUID().uuidString)"
                let defaults = try #require(UserDefaults(suiteName: suite))
                defer { defaults.removePersistentDomain(forName: suite) }
                let drawer = DebugDrawer(defaults: defaults)
                drawer.registerGlobal(ReadoutPlugin())
                drawer.hudLayout.pinned = ["ReadoutPlugin"]
                let sut = DrawerHUDLayer(drawer: drawer)

                let shownOpacity = try? sut.inspect().find(DrawerHUDView.self).opacity()
                drawer.isHUDHidden = true
                let hiddenOpacity = try? sut.inspect().find(DrawerHUDView.self).opacity()

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

            @Test("Unpin in a readout's context menu takes that readout off the HUD and leaves the others")
            func unpinTakesTheReadoutOff() throws {
                let name = "HUDTests.\(#function).\(UUID().uuidString)"
                let suite = try #require(UserDefaults(suiteName: name))
                defer { suite.removePersistentDomain(forName: name) }
                let drawer = DebugDrawer(defaults: suite)
                drawer.registerGlobal(ReadoutPlugin())
                drawer.registerGlobal(ReadoutPlugin(id: "SecondReadout", title: "Second"))
                drawer.toggleHUD(forPlugin: "ReadoutPlugin")
                drawer.toggleHUD(forPlugin: "SecondReadout")
                let card = DrawerHUDCard(readouts: drawer.hudPlugins) { drawer.toggleHUD(forPlugin: $0) }
                // ViewInspector can't open a context menu, so the test inspects the menu each
                // readout's `contextMenu` shows.
                let sut = card.menu(for: AnyDebugDrawerPlugin(ReadoutPlugin()))
                let expected = ["SecondReadout"]

                try sut.inspect().find(button: "Unpin Readout").tap()

                #expect(drawer.hudPlugins.map(\.id) == expected)
                #expect(HUDLayout(from: suite).pinned == expected)
            }
        #endif
    }

    // ViewInspector isn't linked on visionOS; the drawer's own windows draw the HUD and the toast
    // on the Mac and iOS only.
    #if os(macOS) || os(iOS)
        // debugDrawer() shows the shared drawer, so this test stays on it, in the serialized suite
        // of the shared drawer's tests.
        extension SharedDrawerTests {
            @MainActor
            @Suite("HUD under debugDrawer()")
            struct HUDModifierTests {
                @Test("On the Mac and iOS the drawer modifier draws neither the HUD nor the toast: the drawer's own windows do, once")
                func theModifierDrawsNoHUDOrToast() {
                    let sut = DebugDrawer.shared
                    let previous = sut.hudLayout
                    sut.registerGlobal(ReadoutPlugin())
                    sut.hudLayout.pinned = ["ReadoutPlugin"]
                    sut.postToast("Saved", fromPlugin: "ReadoutPlugin")
                    let posted = sut.toast != nil && !sut.hudPlugins.isEmpty
                    let app = Text("App").debugDrawer()

                    let hud = try? app.inspect().find(DrawerHUDView.self)
                    let toast = try? app.inspect().find(DrawerToastView.self)

                    sut.dismissToast()
                    sut.hudLayout = previous
                    sut.unregisterGlobal(id: "ReadoutPlugin")
                    #expect(posted)
                    #expect(hud == nil)
                    #expect(toast == nil)
                }
            }
        }
    #endif
#endif
