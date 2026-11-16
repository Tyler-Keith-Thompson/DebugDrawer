#if DEBUG
    import DebugDrawer
    @testable import DebugDrawerPerformancePlugin
    import Testing

    struct FrameRateTests {
        struct Case: Sendable {
            let fps: Int
            let maximum: Int
            let expected: DebugDrawerIssueGlyph.Severity?
        }

        @Test("A frame rate is smooth from 90% of the display's rate, a warning from half, and an error below half",
              arguments: [
                  Case(fps: 60, maximum: 60, expected: nil),
                  Case(fps: 54, maximum: 60, expected: nil),
                  Case(fps: 53, maximum: 60, expected: .warning),
                  Case(fps: 30, maximum: 60, expected: .warning),
                  Case(fps: 29, maximum: 60, expected: .error),
                  Case(fps: 110, maximum: 120, expected: nil),
                  Case(fps: 60, maximum: 120, expected: .warning),
                  Case(fps: 0, maximum: 0, expected: .error)
              ])
        func severity(of sample: Case) {
            let actual = FrameRate.severity(fps: sample.fps, maximum: sample.maximum)

            #expect(actual == sample.expected)
        }
    }
#endif
