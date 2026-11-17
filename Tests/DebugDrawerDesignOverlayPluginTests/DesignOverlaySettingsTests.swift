#if DEBUG
    import CoreGraphics
    @testable import DebugDrawerDesignOverlayPlugin
    import Foundation
    import Testing

    @Suite
    struct DesignOverlaySettingsTests {
        @Test("New settings show the mockup at 50%, unmoved, scaled automatically, in the normal blend")
        func defaults() {
            let actual = DesignOverlaySettings()

            #expect(actual.isVisible)
            #expect(actual.opacity == 0.5)
            #expect(actual.offset == .zero)
            #expect(actual.scale == .automatic)
            #expect(actual.blend == .normal)
            #expect(actual.opacityText == "50%")
        }

        @Test("A drag adds its translation to the offset, rounded to whole points")
        func moved() {
            var settings = DesignOverlaySettings()
            settings.offset = CGSize(width: 10, height: -4)
            let expected = CGSize(width: 23, height: -12)

            let actual = settings.moved(by: CGSize(width: 12.6, height: -7.6)).offset

            #expect(actual == expected)
        }

        @Test("A drag past the steppers' range stops at its ends")
        func movedClamped() {
            var settings = DesignOverlaySettings()
            settings.offset = CGSize(width: 9990, height: -9990)
            let expected = CGSize(width: 10000, height: -10000)

            let actual = settings.moved(by: CGSize(width: 50, height: -50)).offset

            #expect(actual == expected)
        }

        @Test("A drag of nothing leaves the offset and every other setting as they were")
        func movedByNothing() {
            var settings = DesignOverlaySettings()
            settings.offset = CGSize(width: 3, height: 4)
            settings.blend = .difference
            settings.opacity = 0.8

            let actual = settings.moved(by: .zero)

            #expect(actual == settings)
        }

        @Test("Opacity reads as a whole percentage at the slider's ends and between")
        func opacityText() {
            let opacities = [0.05, 0.333, 0.5, 0.996, 1]
            let expected = ["5%", "33%", "50%", "100%", "100%"]

            let actual = opacities.map { opacity in
                var settings = DesignOverlaySettings()
                settings.opacity = opacity
                return settings.opacityText
            }

            #expect(actual == expected)
        }

        @Test("Settings round-trip through JSON unchanged")
        func codable() throws {
            var expected = DesignOverlaySettings()
            expected.isVisible = false
            expected.opacity = 0.75
            expected.offset = CGSize(width: -8, height: 21)
            expected.scale = .at3x
            expected.blend = .difference

            let actual = try JSONDecoder().decode(DesignOverlaySettings.self, from: JSONEncoder().encode(expected))

            #expect(actual == expected)
        }
    }
#endif
