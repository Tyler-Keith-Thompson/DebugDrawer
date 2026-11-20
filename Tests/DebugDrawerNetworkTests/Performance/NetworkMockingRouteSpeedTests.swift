// What the capability costs a request, in both configurations: URL loading asks the URL protocol
// about every request of a session that lists it, on its own threads, so the question must be
// cheap, with rules in effect and without.
import Combine
import DebugDrawerNetwork
import DebugDrawerReceiver
import Foundation
import Testing

/// Times nothing: each request's latency and bandwidth are its own.
private struct UnusedScheduler: NetworkConditionScheduler {
    func schedule(after _: Duration, _: @escaping @Sendable () -> Void) -> AnyCancellable {
        AnyCancellable {}
    }
}

/// Never fails a request.
private struct ZeroRandomSource: NetworkConditionRandomSource {
    func rollPercent() -> Int {
        0
    }
}

// 10,000 questions against 50 wildcard rules, only the last of which matches, take about a tenth
// of a second on an Apple silicon Mac in debug builds, less in release; the bound is far above
// that, so a loaded machine passes and a route that recompiled patterns per request, or matched
// hosts the app doesn't allow, fails.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct NetworkMockingRouteSpeedTests {
    @Test("10,000 requests asked about against 50 wildcard rules take under 3 s, and requests to other hosts cost less")
    func manyQuestions() throws {
        let rules = (0 ..< 50).map { index in
            NetworkMockRule(
                name: "Rule \(index)", matcher: .init(host: .wildcard("*.example.com"), path: .wildcard("/v\(index)/**")), response: .init()
            )
        }
        let route = NetworkMockingRoute()
        route.activate(
            ActiveNetworkMocks(
                rules: rules, conditions: [], allowedHosts: [.domain("example.com")], expires: .distantFuture, now: { Date() },
                scheduler: UnusedScheduler(), random: ZeroRandomSource()
            ),
            for: ObjectIdentifier(route)
        )
        let matching = try #require(URL(string: "https://api.example.com/v49/orders/7"))
        let elsewhere = try #require(URL(string: "https://api.other.com/v49/orders/7"))
        let count = 10000
        let bound = Duration.seconds(3)
        let clock = ContinuousClock()
        var claimed = 0
        var claimedElsewhere = 0

        let elapsed = clock.measure {
            for _ in 0 ..< count where route.claims(method: "GET", url: matching) {
                claimed += 1
            }
        }
        let elapsedElsewhere = clock.measure {
            for _ in 0 ..< count where route.claims(method: "GET", url: elsewhere) {
                claimedElsewhere += 1
            }
        }

        #expect(claimed == count)
        #expect(claimedElsewhere == 0)
        #expect(elapsed < bound)
        #expect(elapsedElsewhere < elapsed)
    }
}
