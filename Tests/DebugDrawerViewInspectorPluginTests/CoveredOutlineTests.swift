// View borders are drawn in the drawer's overlay window, above the app's: these pin that what the
// app draws over a view (a sheet, a child window, a later window) hides the view's outline there
// as it hides the view, and that the parts of the outline outside it are still drawn.
#if DEBUG && (os(macOS) || os(iOS))
    import CoreGraphics
    @testable import DebugDrawerViewInspectorPlugin
    import Testing

    @Suite
    struct OutlineEdgeTests {
        @Test("An outline under a cover keeps only the parts of its sides outside the cover, inset by half a line")
        func coveredSidesAreCut() {
            // A band 20 pt wide crosses the view from top to bottom, 40 pt from its leading edge.
            let sut = ViewOutline(
                frame: CGRect(x: 0, y: 0, width: 100, height: 50), depth: 1,
                covers: [CGRect(x: 40, y: -10, width: 20, height: 100)]
            )
            let expected = [
                OutlineEdge(start: CGPoint(x: 0.5, y: 0.5), end: CGPoint(x: 40, y: 0.5)),
                OutlineEdge(start: CGPoint(x: 60, y: 0.5), end: CGPoint(x: 99.5, y: 0.5)),
                OutlineEdge(start: CGPoint(x: 0.5, y: 49.5), end: CGPoint(x: 40, y: 49.5)),
                OutlineEdge(start: CGPoint(x: 60, y: 49.5), end: CGPoint(x: 99.5, y: 49.5)),
                OutlineEdge(start: CGPoint(x: 0.5, y: 0.5), end: CGPoint(x: 0.5, y: 49.5)),
                OutlineEdge(start: CGPoint(x: 99.5, y: 0.5), end: CGPoint(x: 99.5, y: 49.5))
            ]

            let actual = sut.visibleEdges

            #expect(actual == expected)
        }

        @Test("A cover over one corner removes that corner's two half sides; covers over all of it remove everything")
        func cornersAndWholeOutlines() {
            let corner = ViewOutline(
                frame: CGRect(x: 0, y: 0, width: 100, height: 50), depth: 1,
                covers: [CGRect(x: 50, y: 25, width: 100, height: 100)]
            )
            let expectedCorner = [
                OutlineEdge(start: CGPoint(x: 0.5, y: 0.5), end: CGPoint(x: 99.5, y: 0.5)),
                OutlineEdge(start: CGPoint(x: 0.5, y: 49.5), end: CGPoint(x: 50, y: 49.5)),
                OutlineEdge(start: CGPoint(x: 0.5, y: 0.5), end: CGPoint(x: 0.5, y: 49.5)),
                OutlineEdge(start: CGPoint(x: 99.5, y: 0.5), end: CGPoint(x: 99.5, y: 25))
            ]
            let whole = ViewOutline(
                frame: CGRect(x: 0, y: 0, width: 100, height: 50), depth: 1,
                covers: [CGRect(x: 0, y: 0, width: 60, height: 50), CGRect(x: 50, y: 0, width: 50, height: 50)]
            )

            let actualCorner = corner.visibleEdges
            let actualWhole = whole.visibleEdges

            #expect(actualCorner == expectedCorner)
            #expect(actualWhole.isEmpty)
        }
    }
#endif

#if os(macOS) && DEBUG
    import AppKit
    @testable import DebugDrawer

    // Sheets and child windows are windows of their own, so these order real windows in: far off
    // screen and fully transparent, so nothing is seen even when a sheet pulls its window on screen.
    @MainActor
    @Suite(.serialized)
    struct CoveredOutlineWindowTests {
        @Test(
            "A sheet is ordered above its window's outlines, whether borders were on before the sheet began or turned on after",
            arguments: [true, false]
        )
        func sheetIsAboveItsWindowsOutlines(bordersFirst: Bool) throws {
            func transparentWindow(_ rect: CGRect, styleMask: NSWindow.StyleMask) -> NSWindow {
                let window = NSWindow(contentRect: rect, styleMask: styleMask, backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.alphaValue = 0
                window.contentView = NSView(frame: CGRect(origin: .zero, size: rect.size))
                window.contentView?.addSubview(NSView(frame: CGRect(x: 20, y: 20, width: rect.width - 40, height: rect.height - 40)))
                return window
            }
            let window = transparentWindow(CGRect(x: -30000, y: -30000, width: 600, height: 400), styleMask: .borderless)
            window.orderFront(nil)
            defer { window.close() }
            let sheet = transparentWindow(CGRect(x: 0, y: 0, width: 300, height: 200), styleMask: .titled)
            let sut = ViewBorderController(appWindows: { [window, sheet].filter(\.isVisible) })
            if bordersFirst {
                sut.isBordersEnabled = true
                sut.overlays.existing(over: window)?.window.alphaValue = 0
            }

            window.beginSheet(sheet)
            defer { window.endSheet(sheet) }
            sut.isBordersEnabled = true
            let overlay = try #require(sut.overlays.existing(over: window))
            let sheetOverlay = try #require(sut.overlays.existing(over: sheet))
            [overlay.window, sheetOverlay.window].forEach { $0.alphaValue = 0 }
            sut.refreshOverlays()
            let frontToBack = (NSWindow.windowNumbers(options: []) ?? []).map(\.intValue)
            let outlines = overlay.model.outlines.count
            sut.isBordersEnabled = false

            try #require(window.attachedSheet === sheet)
            let sheetIndex = try #require(frontToBack.firstIndex(of: sheet.windowNumber))
            let overlayIndex = try #require(frontToBack.firstIndex(of: overlay.window.windowNumber))
            let sheetOverlayIndex = try #require(frontToBack.firstIndex(of: sheetOverlay.window.windowNumber))
            let windowIndex = try #require(frontToBack.firstIndex(of: window.windowNumber))
            #expect(sheetOverlayIndex < sheetIndex)
            #expect(sheetIndex < overlayIndex)
            #expect(overlayIndex < windowIndex)
            #expect(outlines == 2)
        }

        @Test(
            "An opaque child window, even one under the overlay, cuts its frame out of its window's outlines; a see-through one cuts nothing",
            arguments: [true, false]
        )
        func childWindowHidesTheOutlinesUnderIt(opaque: Bool) throws {
            // Whether any length of `edge` lies inside `rect`, not just on its boundary.
            func enters(_ edge: OutlineEdge, _ rect: CGRect) -> Bool {
                let low = CGPoint(x: min(edge.start.x, edge.end.x), y: min(edge.start.y, edge.end.y))
                let high = CGPoint(x: max(edge.start.x, edge.end.x), y: max(edge.start.y, edge.end.y))
                let inside = rect.insetBy(dx: 0.01, dy: 0.01)
                return low.x <= inside.maxX && high.x >= inside.minX && low.y <= inside.maxY && high.y >= inside.minY
            }
            // Far off screen, with no sheet to pull it on, so nothing is seen.
            let window = NSWindow(
                contentRect: CGRect(x: -30000, y: -30000, width: 600, height: 400),
                styleMask: .borderless, backing: .buffered, defer: false
            )
            window.isReleasedWhenClosed = false
            let content = NSView(frame: CGRect(x: 0, y: 0, width: 600, height: 400))
            let under = NSView(frame: CGRect(x: 120, y: 120, width: 50, height: 50))
            let across = NSView(frame: CGRect(x: 0, y: 150, width: 600, height: 20))
            [under, across].forEach(content.addSubview)
            window.contentView = content
            window.orderFront(nil)
            // 100 pt in and up from the window's bottom-leading corner: 200 pt down from its top.
            let palette = NSWindow(
                contentRect: CGRect(x: -29900, y: -29900, width: 200, height: 100),
                styleMask: .borderless, backing: .buffered, defer: false
            )
            palette.isReleasedWhenClosed = false
            palette.backgroundColor = opaque ? .windowBackgroundColor : .clear
            window.addChildWindow(palette, ordered: .above)
            defer {
                window.removeChildWindow(palette)
                [palette, window].forEach { $0.close() }
            }
            let paletteFrame = CGRect(x: 100, y: 200, width: 200, height: 100)
            let underFrame = CGRect(x: 120, y: 230, width: 50, height: 50)
            let acrossFrame = CGRect(x: 0, y: 230, width: 600, height: 20)
            let expectedAcross = opaque ? [paletteFrame] : []
            let sut = ViewBorderController(appWindows: { [window] })

            sut.isBordersEnabled = true
            let actual = try #require(sut.overlays.existing(over: window)).model.outlines
            sut.isBordersEnabled = false

            #expect(actual.contains { $0.frame == underFrame } == !opaque)
            let actualAcross = try #require(actual.first { $0.frame == acrossFrame })
            #expect(actualAcross.covers == expectedAcross)
            #expect(actualAcross.visibleEdges.contains { enters($0, paletteFrame) } == !opaque)
            #expect(actual.contains { $0.frame == CGRect(x: 0, y: 0, width: 600, height: 400) })
        }
    }

// UIKit can't make a window in xctest, which runs package tests on Mac Catalyst without an
// NSApplication, so the iOS tests run on the iOS simulator alone.
#elseif os(iOS) && DEBUG && !targetEnvironment(macCatalyst)
    import UIKit

    // UIKit presents a view controller only in a window of a connected scene. Bazel runs these
    // tests on an iPad inside the test host (//tools/test_host), whose scene the windows here join;
    // `just test-ios` runs them in SwiftPM's runner, which connects none, so the presenting tests
    // are left out there.
    @MainActor
    @Suite(.serialized, .timeLimit(.minutes(1)))
    struct CoveredOutlineTests {
        @Test(
            "On an iPad a form sheet hides the presenting views' outlines inside its frame and keeps every part of them outside it",
            .enabled {
                await MainActor.run {
                    UIDevice.current.userInterfaceIdiom == .pad && UIApplication.shared.connectedScenes.contains { $0 is UIWindowScene }
                }
            }
        )
        func formSheetHidesWhatItCovers() async throws {
            func views(under view: UIView) -> [UIView] {
                [view] + view.subviews.flatMap(views(under:))
            }
            // Whether any length of `edge` lies inside `rect`, not just on its boundary.
            func enters(_ edge: OutlineEdge, _ rect: CGRect) -> Bool {
                let low = CGPoint(x: min(edge.start.x, edge.end.x), y: min(edge.start.y, edge.end.y))
                let high = CGPoint(x: max(edge.start.x, edge.end.x), y: max(edge.start.y, edge.end.y))
                let inside = rect.insetBy(dx: 0.01, dy: 0.01)
                return low.x <= inside.maxX && high.x >= inside.minX && low.y <= inside.maxY && high.y >= inside.minY
            }
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            let presenter = UIViewController()
            presenter.view.backgroundColor = .white
            window.rootViewController = presenter
            window.isHidden = false
            window.layoutIfNeeded()
            let screen = window.bounds
            let outside = UIView(frame: CGRect(x: 20, y: 20, width: 100, height: 40))
            let inside = UIView(frame: CGRect(x: screen.midX - 50, y: screen.midY - 50, width: 100, height: 100))
            let across = UIView(frame: CGRect(x: 20, y: screen.midY - 20, width: screen.width - 40, height: 40))
            // From the middle of the screen down past the sheet's bottom edge.
            let down = UIView(frame: CGRect(x: screen.midX + 100, y: screen.midY, width: 20, height: screen.height / 2 - 20))
            [outside, inside, across, down].forEach(presenter.view.addSubview)
            let sheet = UIViewController()
            sheet.view.backgroundColor = .systemBackground
            sheet.modalPresentationStyle = .formSheet
            await withCheckedContinuation { presenter.present(sheet, animated: false, completion: $0.resume) }
            let overlay = UIWindow(windowScene: scene)
            // The sheet as drawn: the view that holds the sheet's view in the presentation's
            // container (the card with its rounded corners and shadow), found apart from what
            // ViewOutline reads.
            let container = try #require(sheet.presentationController?.containerView)
            let card = try #require(container.subviews.first { sheet.view.isDescendant(of: $0) })
            let sheetFrame = window.convert(card.convert(card.bounds, to: nil), to: overlay)
            let presenting = views(under: presenter.view).map { window.convert($0.convert($0.bounds, to: nil), to: overlay) }

            let actual = ViewOutline.read(from: [window], in: overlay)

            await withCheckedContinuation { presenter.dismiss(animated: false, completion: $0.resume) }
            window.isHidden = true
            try #require(screen.contains(sheetFrame) && sheetFrame.width < screen.width && sheetFrame.height < screen.height)
            try #require(sheetFrame.contains(inside.frame) && sheetFrame.intersects(across.frame) && !sheetFrame.intersects(outside.frame))
            let actualPresenting = actual.filter { presenting.contains($0.frame) }
            #expect(actualPresenting.count >= 3)
            #expect(actualPresenting.allSatisfy { outline in !outline.visibleEdges.contains { enters($0, sheetFrame) } })
            #expect(actual.contains { $0.frame == outside.frame && $0.covers.isEmpty })
            #expect(!actual.contains { $0.frame == inside.frame })
            let acrossEdges = try #require(actual.first { $0.frame == across.frame }).visibleEdges
            let top = across.frame.minY + 0.5
            #expect(acrossEdges.contains(OutlineEdge(start: CGPoint(x: 20.5, y: top), end: CGPoint(x: sheetFrame.minX, y: top))))
            #expect(acrossEdges.contains(OutlineEdge(start: CGPoint(x: sheetFrame.maxX, y: top), end: CGPoint(x: across.frame.maxX - 0.5, y: top))))
            #expect(acrossEdges.contains(OutlineEdge(start: CGPoint(x: 20.5, y: top), end: CGPoint(x: 20.5, y: across.frame.maxY - 0.5))))
            // Its sides start where the drawn sheet ends, and its bottom shows whole.
            let downEdges = try #require(actual.first { $0.frame == down.frame }).visibleEdges
            let bottom = down.frame.maxY - 0.5
            let expectedDown = [
                OutlineEdge(start: CGPoint(x: down.frame.minX + 0.5, y: bottom), end: CGPoint(x: down.frame.maxX - 0.5, y: bottom)),
                OutlineEdge(start: CGPoint(x: down.frame.minX + 0.5, y: sheetFrame.maxY), end: CGPoint(x: down.frame.minX + 0.5, y: bottom)),
                OutlineEdge(start: CGPoint(x: down.frame.maxX - 0.5, y: sheetFrame.maxY), end: CGPoint(x: down.frame.maxX - 0.5, y: bottom))
            ]
            #expect(downEdges == expectedDown)
            #expect(actual.contains { $0.frame == sheetFrame && $0.covers.isEmpty })
        }

        @Test(
            "On an iPad a sheet stacked on a sheet hides the first sheet's outline inside it and keeps its own",
            .enabled {
                await MainActor.run {
                    UIDevice.current.userInterfaceIdiom == .pad && UIApplication.shared.connectedScenes.contains { $0 is UIWindowScene }
                }
            }
        )
        func stackedSheetHidesTheSheetUnderIt() async throws {
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            let presenter = UIViewController()
            presenter.view.backgroundColor = .white
            window.rootViewController = presenter
            window.isHidden = false
            // A page sheet, then a form sheet on it, which an iPad draws narrower.
            let first = UIViewController()
            first.view.backgroundColor = .systemBackground
            first.modalPresentationStyle = .pageSheet
            let second = UIViewController()
            second.view.backgroundColor = .systemBackground
            second.modalPresentationStyle = .formSheet
            await withCheckedContinuation { presenter.present(first, animated: false, completion: $0.resume) }
            await withCheckedContinuation { first.present(second, animated: false, completion: $0.resume) }
            let overlay = UIWindow(windowScene: scene)
            let firstView = try #require(first.presentationController?.presentedView)
            let secondView = try #require(second.presentationController?.presentedView)
            let firstFrame = window.convert(firstView.convert(firstView.bounds, to: nil), to: overlay)
            let secondFrame = window.convert(secondView.convert(secondView.bounds, to: nil), to: overlay)

            let actual = ViewOutline.read(from: [window], in: overlay)

            await withCheckedContinuation { presenter.dismiss(animated: false, completion: $0.resume) }
            window.isHidden = true
            try #require(
                firstFrame.intersects(secondFrame) && !secondFrame.contains(firstFrame),
                "page sheet \(firstFrame), form sheet \(secondFrame)"
            )
            let firstOutline = try #require(actual.first { $0.frame == firstFrame })
            #expect(firstOutline.covers == [secondFrame])
            #expect(!firstOutline.visibleEdges.isEmpty)
            #expect(actual.contains { $0.frame == secondFrame && $0.covers.isEmpty })
        }

        @Test(
            "A see-through presentation over the full screen hides nothing; an opaque one hides what it covers",
            .enabled { await MainActor.run { UIApplication.shared.connectedScenes.contains { $0 is UIWindowScene } } },
            arguments: [false, true]
        )
        func overFullScreenHidesOnlyWhenOpaque(opaque: Bool) async throws {
            let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
            let window = UIWindow(windowScene: scene)
            let presenter = UIViewController()
            presenter.view.addSubview(UIView(frame: CGRect(x: 20, y: 20, width: 100, height: 40)))
            window.rootViewController = presenter
            window.isHidden = false
            let cover = UIViewController()
            cover.view.backgroundColor = opaque ? .white : .clear
            cover.modalPresentationStyle = .overFullScreen
            await withCheckedContinuation { presenter.present(cover, animated: false, completion: $0.resume) }
            let presented = CGRect(x: 20, y: 20, width: 100, height: 40)

            let actual = ViewOutline.read(from: [window], in: UIWindow(windowScene: scene))

            await withCheckedContinuation { presenter.dismiss(animated: false, completion: $0.resume) }
            window.isHidden = true
            #expect(actual.contains { $0.frame == presented && $0.covers.isEmpty } == !opaque)
            #expect(actual.contains { $0.frame == presented } == !opaque)
        }

        @Test(
            "A later window whose root view is opaque hides the earlier windows' outlines under it; a see-through one hides none",
            arguments: [false, true]
        )
        func opaqueWindowHidesTheWindowsUnderIt(opaque: Bool) {
            // Inside the test host (Bazel) the windows join its scene, since there UIKit converts
            // nothing between windows that have none; SwiftPM's runner connects no scene.
            func makeWindow(_ frame: CGRect) -> UIWindow {
                let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
                let window = scene.map { UIWindow(windowScene: $0) } ?? UIWindow()
                window.frame = frame
                return window
            }
            let back = makeWindow(CGRect(x: 0, y: 0, width: 400, height: 600))
            back.addSubview(UIView(frame: CGRect(x: 50, y: 50, width: 50, height: 50)))
            let front = makeWindow(CGRect(x: 0, y: 0, width: 200, height: 200))
            let root = UIViewController()
            root.view.backgroundColor = opaque ? .white : .clear
            front.rootViewController = root
            front.isHidden = false
            front.layoutIfNeeded()
            let under = CGRect(x: 50, y: 50, width: 50, height: 50)
            let frontRoot = CGRect(x: 0, y: 0, width: 200, height: 200)

            let actual = ViewOutline.read(from: [back, front], in: makeWindow(CGRect(x: 0, y: 0, width: 400, height: 600)))

            front.isHidden = true
            #expect(actual.contains { $0.frame == under && $0.covers.isEmpty } == !opaque)
            #expect(actual.contains { $0.frame == under } == !opaque)
            #expect(actual.contains { $0.frame == frontRoot && $0.covers.isEmpty })
        }
    }
#endif
