#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerScreenRecordingPlugin
    import QuartzCore
    import Testing

    @MainActor
    @Suite
    struct DrawerChromeLayersTests {
        @Test(
            "The layers painted from a chrome start to its end are listed, topmost only, boundary included; the app's layers and ancestors are not"
        )
        func between() {
            // root
            // ├─ app            (the app's content)
            // ├─ startHost
            // │  └─ start
            // ├─ hud
            // ├─ panel
            // │  └─ panelText
            // ├─ endHost
            // │  └─ end
            // └─ sheet          (after the drawer: a presented sheet)
            let root = CALayer()
            let app = CALayer()
            let startHost = CALayer()
            let start = CALayer()
            start.name = debugDrawerChromeStartLayerName
            let hud = CALayer()
            let panel = CALayer()
            let panelText = CALayer()
            let endHost = CALayer()
            let end = CALayer()
            end.name = debugDrawerChromeEndLayerName
            let sheet = CALayer()
            startHost.addSublayer(start)
            panel.addSublayer(panelText)
            endHost.addSublayer(end)
            for layer in [app, startHost, hud, panel, endHost, sheet] {
                root.addSublayer(layer)
            }
            let expected = [start, hud, panel, end].map(ObjectIdentifier.init)

            let actual = DrawerChromeLayers.layers(in: root).map(ObjectIdentifier.init)

            #expect(actual == expected)
        }

        @Test("Boundary layers at different depths list the start's later siblings and the end's earlier ones")
        func differentDepths() {
            // root ─┬─ app
            //       ├─ container ─┬─ appToo
            //       │             ├─ start
            //       │             └─ hud
            //       ├─ panel
            //       └─ group ─┬─ toast
            //                 ├─ end
            //                 └─ afterEnd
            let root = CALayer()
            let app = CALayer()
            let container = CALayer()
            let appToo = CALayer()
            let start = CALayer()
            start.name = debugDrawerChromeStartLayerName
            let hud = CALayer()
            let panel = CALayer()
            let group = CALayer()
            let toast = CALayer()
            let end = CALayer()
            end.name = debugDrawerChromeEndLayerName
            let afterEnd = CALayer()
            for layer in [appToo, start, hud] {
                container.addSublayer(layer)
            }
            for layer in [toast, end, afterEnd] {
                group.addSublayer(layer)
            }
            for layer in [app, container, panel, group] {
                root.addSublayer(layer)
            }
            let expected = [start, hud, panel, toast, end].map(ObjectIdentifier.init)

            let actual = DrawerChromeLayers.layers(in: root).map(ObjectIdentifier.init)

            #expect(actual == expected)
        }

        @Test("Two drawers, the window's and a sheet's own, are both listed")
        func twoDrawers() {
            let root = CALayer()
            let names = [
                nil, debugDrawerChromeStartLayerName, nil, debugDrawerChromeEndLayerName,
                nil, debugDrawerChromeStartLayerName, nil, debugDrawerChromeEndLayerName
            ]
            let layers = names.map { name in
                let layer = CALayer()
                layer.name = name
                root.addSublayer(layer)
                return layer
            }
            let expected = [1, 2, 3, 5, 6, 7].map { ObjectIdentifier(layers[$0]) }

            let actual = DrawerChromeLayers.layers(in: root).map(ObjectIdentifier.init)

            #expect(actual == expected)
        }

        @Test("A start with no end after it marks nothing, and a tree without the boundary has nothing to hide")
        func unmatched() {
            let unmatched = CALayer()
            let start = CALayer()
            start.name = debugDrawerChromeStartLayerName
            unmatched.addSublayer(CALayer())
            unmatched.addSublayer(start)
            unmatched.addSublayer(CALayer())
            let plain = CALayer()
            plain.addSublayer(CALayer())

            #expect(DrawerChromeLayers.layers(in: unmatched).isEmpty)
            #expect(DrawerChromeLayers.layers(in: plain).isEmpty)
        }

        @Test("An end before any start marks nothing before it")
        func endFirst() {
            let root = CALayer()
            let names = [nil, debugDrawerChromeEndLayerName, nil]
            for name in names {
                let layer = CALayer()
                layer.name = name
                root.addSublayer(layer)
            }

            #expect(DrawerChromeLayers.layers(in: root).isEmpty)
        }

        @Test("While drawing, the drawer's layers are hidden; after, they are shown again, and a layer the app hid stays hidden")
        func hidden() {
            let root = CALayer()
            let app = CALayer()
            let start = CALayer()
            start.name = debugDrawerChromeStartLayerName
            let panel = CALayer()
            let hiddenByApp = CALayer()
            hiddenByApp.isHidden = true
            let end = CALayer()
            end.name = debugDrawerChromeEndLayerName
            for layer in [app, start, panel, hiddenByApp, end] {
                root.addSublayer(layer)
            }

            let during = DrawerChromeLayers.hidden(in: root) {
                [app.isHidden, panel.isHidden, hiddenByApp.isHidden]
            }

            #expect(during == [false, true, true])
            #expect(!panel.isHidden)
            #expect(!app.isHidden)
            #expect(hiddenByApp.isHidden)
        }
    }
#endif
