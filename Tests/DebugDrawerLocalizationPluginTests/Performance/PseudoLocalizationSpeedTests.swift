// What pseudo-localizing costs a lookup. The transform lives in DebugDrawerLocalization and exists
// in every build, as the receiver's localization review draws strings with it in release, so both
// configurations measure it.
import DebugDrawerLocalization
import Testing

// Every string the app looks up while pseudo-localizing goes through the transform, on the
// thread that looks it up, so its cost must stay small and linear in the string's
// length. 20,000 strings of about 60 characters with three specifiers each take about half a
// second on an Apple silicon Mac in debug builds, less in release; the bound is six times that,
// so a loaded machine passes and a transform that rescans the string per character fails.
@Suite(.timeLimit(.minutes(1)))
struct PseudoLocalizationSpeedTests {
    @Test("Pseudo-localizing 20,000 strings of 60 characters with specifiers takes under 3 s")
    func transformMany() {
        let input = "Your order of %lld items ships to %@ on %2$@, with 10%% off."
        let count = 20000
        let bound = Duration.seconds(3)
        let clock = ContinuousClock()
        var lengths = 0

        let elapsed = clock.measure {
            for _ in 0 ..< count {
                lengths += PseudoLocalization.transform(input).count
            }
        }

        #expect(lengths > count * input.count)
        #expect(elapsed < bound)
    }

    @Test("A string of 100,000 characters pseudo-localizes in under 3 s: the transform is linear in length")
    func transformLong() {
        let input = String(repeating: "Delivery: %@. ", count: 7143)
        let bound = Duration.seconds(3)
        let clock = ContinuousClock()
        var actual = ""

        let elapsed = clock.measure {
            actual = PseudoLocalization.transform(input)
        }

        #expect(actual.hasPrefix("[Ðéļîṽéŕý: %@. "))
        #expect(elapsed < bound)
    }
}
