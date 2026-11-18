#if DEBUG && (os(macOS) || os(iOS))
    @testable import DebugDrawerViewInspectorPlugin
    import QuartzCore
    import Testing

    @MainActor
    @Suite
    struct AnimationSpeedTests {
        @Test("Slowing animations divides each layer's own speed, and normal speed gives back exactly the speed it had")
        func slowdownRestoresTheOriginalSpeed() {
            let sut = AnimationSlowdown()
            let normal = CALayer()
            let hurried = CALayer()
            hurried.speed = 1.7
            let expectedSlowed: [Float] = [0.1, 0.17]
            let expectedRestored: [Float] = [1, 1.7]

            sut.apply(10, to: [normal, hurried])
            let slowed = [normal.speed, hurried.speed]
            sut.apply(4, to: [normal, hurried])
            sut.apply(1, to: [normal, hurried])
            let actual = [normal.speed, hurried.speed]

            #expect(zip(slowed, expectedSlowed).allSatisfy { abs($0 - $1) < 0.0001 })
            #expect(actual == expectedRestored)
        }

        @Test("A window that opens while animations are slowed is slowed too, and given back its speed with the others")
        func newLayersAreSlowedAndRestored() {
            let sut = AnimationSlowdown()
            let first = CALayer()
            let opened = CALayer()
            opened.speed = 0.5
            let expectedSlowed: Float = 0.1
            let expectedRestored: [Float] = [1, 0.5]

            sut.apply(5, to: [first])
            sut.apply(5, to: [first, opened])
            let slowed = opened.speed
            sut.restore()
            let actual = [first.speed, opened.speed]

            #expect(abs(slowed - expectedSlowed) < 0.0001)
            #expect(actual == expectedRestored)
        }

        @Test("The slider's label says how many times slower animations run", arguments: [
            (1.0, "Normal", "Normal speed"),
            (2.5, "2.5× slower", "2.5 times slower"),
            (10.0, "10× slower", "10 times slower")
        ])
        func labels(slowdown: Double, expected: String, expectedSpoken: String) {
            let actual = AnimationSpeedRow.label(for: slowdown)
            let actualSpoken = AnimationSpeedRow.spokenLabel(for: slowdown)

            #expect(actual == expected)
            #expect(actualSpoken == expectedSpoken)
        }
    }
#endif

#if os(macOS) && DEBUG
    import SwiftUI
    import ViewInspector

    @MainActor
    @Suite
    struct AnimationSpeedRowTests {
        @Test("At ten, the row shows 10× slower beside a slider VoiceOver reads as ten times slower")
        func rowShowsTheSlowdown() throws {
            let sut = AnimationSpeedRow(slowdown: .constant(10))
            let expected = "10× slower"
            let expectedValue = "10 times slower"

            let actual = try sut.inspect().find(text: expected).string()
            let actualValue = try sut.inspect().find(ViewType.Slider.self).accessibilityValue().string()

            #expect(actual == expected)
            #expect(actualValue == expectedValue)
        }

        @Test("At one, the row says Normal")
        func rowShowsNormal() throws {
            let sut = AnimationSpeedRow(slowdown: .constant(1))
            let expected = "Normal"

            let actual = try sut.inspect().find(text: expected).string()

            #expect(actual == expected)
        }
    }
#endif
