// Views render on the Mac; ViewInspector is linked on Apple platforms only.
#if os(macOS)
    @testable import DebugDrawer
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct SparklineTests {
        @Test("VoiceOver reads the label, then the latest, lowest and highest samples")
        func accessibility() throws {
            let sut = DebugDrawerSparkline("Frame rate history", data: [60, 41, 58.5])
            let expectedLabel = "Frame rate history"
            let expectedValue = "Latest 58.5, lowest 41, highest 60"

            let graph = try sut.inspect().find(viewWithAccessibilityLabel: expectedLabel)
            let actual = try graph.accessibilityValue().string()

            #expect(actual == expectedValue)
        }

        @Test("With no samples the sparkline draws nothing")
        func empty() throws {
            let sut = DebugDrawerSparkline("CPU history", data: [])

            #expect(throws: (any Error).self) {
                try sut.inspect().find(viewWithAccessibilityLabel: "CPU history")
            }
        }

        @Test("With one sample there is no line to draw, so the sparkline draws nothing")
        func oneSample() throws {
            let sut = DebugDrawerSparkline("CPU history", data: [12])

            #expect(throws: (any Error).self) {
                try sut.inspect().find(viewWithAccessibilityLabel: "CPU history")
            }
        }

        @Test("Two samples are enough to draw")
        func twoSamples() throws {
            let sut = DebugDrawerSparkline("CPU history", data: [12, 80], range: 0 ... 100)
            let expected = "Latest 80, lowest 12, highest 80"

            let actual = try sut.inspect().find(viewWithAccessibilityLabel: "CPU history").accessibilityValue().string()

            #expect(actual == expected)
        }
    }
#endif
