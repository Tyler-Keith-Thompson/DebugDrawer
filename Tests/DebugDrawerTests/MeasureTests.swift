@testable import DebugDrawer
import Testing

struct MeasureTests {
    @Test("A figure and a unit split at the unit, keeping the space before it", arguments: [
        ("63.5 MB", "63.5", " MB"),
        ("11s", "11", "s"),
        ("1,024 KB", "1,024", " KB"),
        ("-3 dB", "-3", " dB"),
        ("98%", "98", "%"),
        ("120 µs", "120", " µs")
    ])
    func splits(value: String, expectedFigure: String, expectedUnit: String) throws {
        let actual = try #require(Measure(value))

        #expect(actual.figure == expectedFigure)
        #expect(actual.unit == expectedUnit)
    }

    @Test("Values that aren't a figure and a short unit don't split", arguments: [
        "", "42", "arm64", "Version 27.2", "1.0.0 (1)", "2m 14s", "12 seconds", "MB"
    ])
    func noUnit(value: String) {
        let actual = Measure(value)

        #expect(actual == nil)
    }
}
