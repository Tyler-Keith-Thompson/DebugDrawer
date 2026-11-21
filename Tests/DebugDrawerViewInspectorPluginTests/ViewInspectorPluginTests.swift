#if DEBUG
    @testable import DebugDrawerViewInspectorPlugin
    import Testing

    @MainActor
    @Suite
    struct ViewInspectorPluginTests {
        @Test("The overlays and click indicators start off, with an 8 pt grid and normal animation speed")
        func viewBorderControllerDefaults() {
            let sut = ViewBorderController(appWindows: { [] })

            #expect(!sut.isBordersEnabled)
            #expect(!sut.isGridEnabled)
            #expect(sut.gridSpacing == 8)
            #expect(sut.animationSpeed == 1.0)
            #expect(!sut.isClickIndicatorEnabled)
        }

        @Test("The plugin is titled View Inspector, with a dashed rectangle for its icon")
        func pluginIdentity() {
            let expectedTitle = "View Inspector"
            let expectedIcon = "rectangle.dashed"

            let actual = ViewInspectorPlugin()

            #expect(actual.title == expectedTitle)
            #expect(actual.icon == expectedIcon)
        }

        @Test("Flashing tracked views starts off")
        func flashesStartOff() {
            let actual = RenderFlashSetting().isOn

            #expect(!actual)
        }
    }
#endif
