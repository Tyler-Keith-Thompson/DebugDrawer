// What drawing a frame costs. The plugin exists in debug builds only, so it is measured there;
// `--config=release` builds this target without it, and runs ReleaseInstallTests instead.
#if DEBUG && os(macOS)
    import AppKit
    @testable import DebugDrawer
    @testable import DebugDrawerScreenRecordingPlugin
    import SwiftUI
    import Testing

    // The recorder draws a frame on each display frame, up to 30 a second, on the main actor, so a
    // frame must cost well under 33 ms or the app stutters while it records. A window the size of a
    // 13-inch iPad (1032 by 1376 points, drawn at 1920 pixels tall) holding a 60-row list, with a
    // drawer-sized panel between the chrome boundary's layers, takes about 19 ms a frame on an
    // Apple silicon Mac in debug builds, finding and hiding the drawer's layers included (the iPad
    // simulator kept 30 frames a second while recording the example app). The bound is half as
    // much again as the frame's budget, so a loaded machine passes and a change that, say, draws
    // every frame twice fails.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct FrameCostTests {
        @Test("A 1440 by 1920 frame of a 60-row window with the drawer left out takes under 50 ms on average")
        func frameCost() throws {
            let content = List(0 ..< 60, id: \.self) { row in
                HStack {
                    Image(systemName: "circle.fill")
                    Text("Row \(row): some text to draw")
                    Spacer()
                    Text("\(row * 37)")
                }
            }
            .overlay { DrawerChromeBoundaryMarker(layerName: debugDrawerChromeStartLayerName) }
            .overlay(alignment: .trailing) {
                VStack(alignment: .leading) {
                    ForEach(0 ..< 30) { Text("Drawer row \($0)") }
                }
                .frame(width: 340, alignment: .leading)
                .frame(maxHeight: .infinity)
                .background(.regularMaterial)
            }
            .overlay { DrawerChromeBoundaryMarker(layerName: debugDrawerChromeEndLayerName) }
            .frame(width: 1032, height: 1376)
            let host = NSHostingView(rootView: content)
            let frame = CGRect(x: 0, y: 0, width: 1032, height: 1376)
            let window = NSWindow(contentRect: frame, styleMask: .borderless, backing: .buffered, defer: false)
            window.contentView = host
            host.frame = frame
            host.layoutSubtreeIfNeeded()
            host.displayIfNeeded()
            let sut = try #require(RecordedWindows(window: window))
            let frames = 30
            let clock = ContinuousClock()
            var images: [CGImage] = []

            let time = clock.measure {
                for _ in 0 ..< frames {
                    if let image = sut.render(touches: [CGPoint(x: 100, y: 100)]) {
                        images.append(image)
                    }
                }
            }

            let perFrame = time / frames
            print("Screen Recording: a 1440x1920 frame takes \(perFrame)")
            #expect(images.count == frames)
            #expect(images.first?.height == 1920)
            #expect(perFrame < .milliseconds(50))
        }
    }
#endif
