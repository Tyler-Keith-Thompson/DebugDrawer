#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerDesignOverlayPlugin
    import Foundation
    import Testing

    @MainActor
    @Suite
    struct DesignOverlayPluginTests {
        @Test("The plugin is Design Overlay, in Interface, with a HUD readout and a header accessory")
        func identity() {
            let sut = DesignOverlayPlugin(model: DesignOverlayModel(storage: FakeMockupStorage()))

            #expect(sut.id == "DesignOverlayPlugin")
            #expect(sut.title == "Design Overlay")
            #expect(sut.category == "Interface")
            #expect(sut.icon == "square.on.square.dashed")
            #expect(AnyDebugDrawerPlugin(sut).hasHUD)
            #expect(AnyDebugDrawerPlugin(sut).headerAccessory != nil)
        }

        @Test("The drawer's search hides and shows the mockup, and switches the difference blend, found by \"mockup\" and \"difference\"")
        func actions() throws {
            let model = DesignOverlayModel(storage: FakeMockupStorage())
            let sut = DesignOverlayPlugin(model: model)
            let visibility = try #require(sut.actions.first { $0.keywords.contains("mockup") })
            let difference = try #require(sut.actions.first { $0.keywords.contains("difference") })

            visibility.perform()
            let afterHide = model.settings.isVisible
            visibility.perform()
            difference.perform()
            let afterDifference = model.settings.blend
            difference.perform()

            #expect(sut.actions.map(\.title) == ["Show or hide the design overlay", "Difference blend for the design overlay"])
            #expect(!afterHide)
            #expect(model.settings.isVisible)
            #expect(afterDifference == .difference)
            #expect(model.settings.blend == .normal)
        }

        @Test("The status says nothing before a mockup, then the opacity, the blend unless normal, Hidden, or Moving")
        func status() {
            var settings = DesignOverlaySettings()
            settings.opacity = 0.35

            let none = DesignOverlayStatus(hasMockup: false, settings: settings, isMoving: true)
            let normal = DesignOverlayStatus(hasMockup: true, settings: settings, isMoving: false)
            settings.blend = .difference
            let difference = DesignOverlayStatus(hasMockup: true, settings: settings, isMoving: false)
            let moving = DesignOverlayStatus(hasMockup: true, settings: settings, isMoving: true)
            settings.isVisible = false
            let hidden = DesignOverlayStatus(hasMockup: true, settings: settings, isMoving: false)

            #expect(none == .noMockup)
            #expect(none.summary == nil)
            #expect(normal.summary == "35%")
            #expect(difference.summary == "35% · Difference")
            #expect(moving.summary == "Moving")
            #expect(hidden.summary == "Hidden")
        }
    }
#endif
