// What the capability costs a reading, in both configurations: the host passes each of Core
// Location's deliveries through it, on whatever thread its manager's run loop runs, so the read
// must be cheap, spoofing or not.
import CoreLocation
import DebugDrawerLocation
import DebugDrawerReceiver
import Foundation
import Testing

// 100,000 readings take a few hundredths of a second on an Apple silicon Mac in debug builds, less
// in release; the bound is far above that, so a loaded machine passes and a read that hopped to
// the main actor, or touched the defaults, fails.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct LocationSpoofingReadSpeedTests {
    @Test("100,000 readings passed through the spoofing take under 3 s, while none is spoofed")
    func manyReadings() throws {
        let suite = "LocationSpoofingReadSpeedTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let sut = LocationSpoofing(sessions: DebugDrawerSessions(maximumDuration: 300), defaults: defaults) { _ in }
        let real = [CLLocation(latitude: 37.3349, longitude: -122.009)]
        let clock = ContinuousClock()
        var delivered = 0

        let elapsed = clock.measure {
            for _ in 0 ..< 100_000 {
                delivered += sut.locations(replacing: real).count
            }
        }

        #expect(delivered == 100_000)
        #expect(elapsed < .seconds(3))
    }
}
