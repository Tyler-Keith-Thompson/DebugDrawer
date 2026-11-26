// What the redaction refuses: a value pattern that isn't a regular expression. Real in every build,
// so these run in debug and release alike.
import DebugDrawerAnalytics
import Testing

@Suite
struct AnalyticsRedactionValidationTests {
    @Test("A value pattern that isn't a regular expression throws InvalidPattern, rather than letting what it was meant to mask through")
    func invalidPattern() {
        let pattern = "(unclosed"

        #expect(throws: AnalyticsRedaction.InvalidPattern.self) {
            _ = try AnalyticsRedaction(values: [pattern])
        }
    }

    @Test("Adding a value pattern that isn't a regular expression throws InvalidPattern")
    func invalidAddedPattern() {
        let pattern = "[z-a]"

        #expect(throws: AnalyticsRedaction.InvalidPattern.self) {
            _ = try AnalyticsRedaction.standard.adding(values: [pattern])
        }
    }

    @Test("One bad pattern among good ones throws InvalidPattern")
    func badAmongGood() {
        let patterns = [#"\bACCT-\d{6}\b"#, "(unclosed"]

        #expect(throws: AnalyticsRedaction.InvalidPattern.self) {
            _ = try AnalyticsRedaction(values: patterns)
        }
    }

    @Test("The standard rules' value patterns all compile: an email address and a JSON Web Token are masked")
    func standardPatternsCompile() {
        let sut = AnalyticsRedaction.standard

        let email = sut.masksValue("ada@example.com")
        let token = sut.masksValue("eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2lnbmF0dXJl")

        #expect(email)
        #expect(token)
    }
}
