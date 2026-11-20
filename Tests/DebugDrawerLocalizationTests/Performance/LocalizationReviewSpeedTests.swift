// What the review costs a lookup, in both configurations: a host reads its strings through it on
// whatever thread draws them, so a mode must add little to the bundle's own lookup.
import DebugDrawerLocalization
import Foundation
import Testing

// 20,000 pseudo-localized lookups of a short string take about a fifth of a second on an Apple
// silicon Mac in debug builds, less in release; the bound is ten times that, so a loaded machine
// passes and a lookup that rereads a table or waits on another thread fails.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct LocalizationReviewSpeedTests {
    @Test("20,000 pseudo-localized lookups through the review take under 2 s")
    func manyLookups() throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "LocalizationReviewSpeedTests-\(UUID().uuidString)/Fixture.bundle", directoryHint: .isDirectory)
        let lproj = url.appending(path: "en.lproj", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: lproj, withIntermediateDirectories: true)
        try Data(#""order.status" = "Your order of %lld items ships to %@ on %2$@.";"#.utf8)
            .write(to: lproj.appending(path: "Localizable.strings"))
        let bundle = try #require(Bundle(url: url))
        let sut = LocalizationReview()
        sut.perform(.setMode(.pseudoLocalized))
        let count = 20000
        let bound = Duration.seconds(2)
        let clock = ContinuousClock()
        var lengths = 0

        let elapsed = clock.measure {
            for _ in 0 ..< count {
                lengths += sut.localizedString(forKey: "order.status", bundle: bundle).count
            }
        }

        #expect(lengths > count * 40)
        #expect(elapsed < bound)
    }
}
