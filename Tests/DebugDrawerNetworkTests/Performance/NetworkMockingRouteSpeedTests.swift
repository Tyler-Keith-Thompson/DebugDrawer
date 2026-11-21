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

// 10,000 questions against 50 wildcard rules, only the last of which matches, take about 0.75 s of
// CPU time on an Apple silicon Mac in debug builds and about 0.5 s in release; the bound is several
// times that, so a route that recompiled patterns per request, or matched hosts the app doesn't allow,
// fails. Each batch is timed in the test thread's CPU time (CLOCK_THREAD_CPUTIME_ID), which stops
// while the thread is descheduled, so other processes loading the machine don't show up as cost;
// the route answers in the call, on this thread. The test keeps each side's fastest of several
// batches, run in turn, which leaves out a batch slowed by a context switch's cold caches or a
// stretch on an efficiency core, and compares those.
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
        let batches = 5
        let count = 10000
        let bound = Duration.seconds(3)
        var claimed = 0
        var claimedElsewhere = 0
        var fastest = Duration.seconds(60)
        var fastestElsewhere = Duration.seconds(60)

        for _ in 0 ..< batches {
            claimed = 0
            claimedElsewhere = 0
            let start = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            for _ in 0 ..< count where route.claims(method: "GET", url: matching) {
                claimed += 1
            }
            let middle = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            for _ in 0 ..< count where route.claims(method: "GET", url: elsewhere) {
                claimedElsewhere += 1
            }
            let end = clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)
            fastest = min(fastest, .nanoseconds(middle - start))
            fastestElsewhere = min(fastestElsewhere, .nanoseconds(end - middle))
        }

        print("Network mocking: \(count) requests take \(fastest) of CPU time against the rules, \(fastestElsewhere) to other hosts")
        #expect(claimed == count)
        #expect(claimedElsewhere == 0)
        #expect(fastest < bound)
        #expect(fastestElsewhere < fastest)
    }
}
