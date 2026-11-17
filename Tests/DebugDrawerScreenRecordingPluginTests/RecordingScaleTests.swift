#if DEBUG
    import CoreGraphics
    @testable import DebugDrawerScreenRecordingPlugin
    import Testing

    @Suite
    struct RecordingScaleTests {
        @Test("A window whose longest side fits 1920 pixels at the screen's scale is recorded at that scale")
        func screenScale() {
            let size = CGSize(width: 390, height: 844)
            let expected: CGFloat = 2

            let actual = RecordingScale.scale(for: size, screenScale: 2)

            #expect(actual == expected)
        }

        @Test("A larger window is scaled down so its longest side is 1920 pixels")
        func capped() {
            let size = CGSize(width: 1032, height: 1376)
            let expected: CGFloat = 1920.0 / 1376

            let actual = RecordingScale.scale(for: size, screenScale: 2)

            #expect(actual == expected)
            #expect(size.height * actual == 1920)
        }

        @Test("At exactly 1920 pixels the screen's scale is kept")
        func boundary() {
            let size = CGSize(width: 960, height: 600)
            let expected: CGFloat = 2

            let actual = RecordingScale.scale(for: size, screenScale: 2)

            #expect(actual == expected)
        }

        @Test("An empty window, or a screen with no scale, records at 1")
        func empty() {
            let expected: CGFloat = 1

            let zeroSize = RecordingScale.scale(for: .zero, screenScale: 2)
            let zeroScale = RecordingScale.scale(for: CGSize(width: 100, height: 100), screenScale: 0)

            #expect(zeroSize == expected)
            #expect(zeroScale == expected)
        }
    }
#endif
