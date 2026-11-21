// What the network-mocking capability costs a request: URL loading asks its URL protocol about
// every request of a session that lists it, on its own threads, so the question must be cheap, with
// rules in effect and without. Asked here as URL loading asks it, through the public
// `NetworkMockingURLProtocol.canInit(with:)`. The capability is real in every build, so DEBUG
// (which `just bench` defines) changes nothing measured here.
import Benchmark
import DebugDrawerNetwork
import DebugDrawerReceiver
import Foundation

/// The capability and its sessions, made on the main actor by the setup of the benchmarks with
/// rules in effect, then kept for the process: the URL protocol answers from them.
@MainActor var mocking: NetworkMocking?
@MainActor var sessions: DebugDrawerSessions?

// Traps: each literal is a whole URL, which URL(string:) always parses.
/// A request to the hosts the rules are for, which only the last rule matches.
let matching = URLRequest(url: URL(string: "https://api.example.com/v49/orders/7")!)
/// A request to a host the capability doesn't allow.
let elsewhere = URLRequest(url: URL(string: "https://api.other.com/v49/orders/7")!)

/// Opens a session and sets 50 wildcard rules for `*.example.com`, each for its own version path,
/// as a sidecar would, and traps unless the URL protocol then claims `matching` and not
/// `elsewhere`.
@MainActor func setRules() {
    let opened = DebugDrawerSessions(maximumDuration: 3600)
    let capability = NetworkMocking(sessions: opened, allowedHosts: [.domain("example.com")])
    opened.perform(.open(duration: 3600))
    let rules = (0 ..< 50).map { index in
        NetworkMockRule(
            name: "Rule \(index)", matcher: .init(host: .wildcard("*.example.com"), path: .wildcard("/v\(index)/**")), response: .init()
        )
    }
    capability.perform(.setRules(rules))
    guard NetworkMockingURLProtocol.canInit(with: matching), !NetworkMockingURLProtocol.canInit(with: elsewhere) else {
        fatalError("The URL protocol didn't claim the matching request alone once the rules were set")
    }
    sessions = opened
    mocking = capability
}

let benchmarks: @Sendable () -> Void = {
    // Each benchmark runs in a process of its own, so one benchmark's rules never reach another.
    // Gated (just bench-check) at 10% over the main baseline's median: the process's retired
    // instructions and its mallocs; reported only: wall clock and CPU time, which move with
    // whatever else the Mac is doing. A thousand questions an iteration, reported per question;
    // a fixed number of iterations.
    Benchmark.defaultConfiguration = .init(
        metrics: [.wallClock, .cpuTotal, .instructions, .mallocCountTotal],
        warmupIterations: 3,
        scalingFactor: .kilo,
        maxDuration: .seconds(120),
        maxIterations: 50,
        thresholds: [
            .instructions: .init(relative: [.p50: 10.0]),
            .mallocCountTotal: .init(relative: [.p50: 10.0]),
            // Reported, not gated.
            .wallClock: .init(),
            .cpuTotal: .init()
        ]
    )

    // The question with no session and no rule: what every request of a session listing the
    // protocol pays while no sidecar mocks anything.
    Benchmark("NetworkMocking: BASELINE canInit, no rules in effect") { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(NetworkMockingURLProtocol.canInit(with: matching))
        }
    }

    // A request the last of 50 wildcard rules answers: every rule is tried.
    Benchmark(
        "NetworkMocking: canInit, 50 wildcard rules, the last matches",
        configuration: .init(setup: { await MainActor.run { setRules() } })
    ) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(NetworkMockingURLProtocol.canInit(with: matching))
        }
    }

    // A request to a host the capability doesn't allow, with the same rules: declined before any
    // rule is tried.
    Benchmark(
        "NetworkMocking: canInit, 50 wildcard rules, another host",
        configuration: .init(setup: { await MainActor.run { setRules() } })
    ) { benchmark in
        for _ in benchmark.scaledIterations {
            blackHole(NetworkMockingURLProtocol.canInit(with: elsewhere))
        }
    }
}
