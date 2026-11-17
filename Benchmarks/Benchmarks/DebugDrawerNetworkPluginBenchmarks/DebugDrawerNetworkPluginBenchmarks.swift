// The interception measured here exists only in debug builds of the library (`#if DEBUG`), and a
// release build of it has no-op stand-ins, which would measure nothing. `just bench` builds
// optimized with DEBUG defined; this stops any other build from passing for a measurement.
#if !DEBUG
    #error("Build the benchmarks with `just bench`, which defines DEBUG: the interception they measure is DEBUG-only.")
#endif

import Benchmark
import DebugDrawer
import DebugDrawerNetworkPlugin
import Foundation

/// Answers every request on this process's loopback interface, so a request costs a real
/// URLSession round trip without leaving the machine.
let server = LoopbackHTTPServer()

/// The app's own session. Created on first use, which the installed benchmark's setup reaches only
/// after installing, as an app creates its sessions after `installNetwork()`.
let session = URLSession(configuration: .ephemeral)

let benchmarks: @Sendable () -> Void = {
    // Each benchmark runs in a process of its own, so one benchmark's install never reaches another.
    // Gated (just bench-check) at 10% over the main baseline's median: the process's retired
    // instructions and its mallocs, which repeat from run to run within a few percent;
    // reported only: wall clock and CPU time, which move with whatever else the Mac is doing.
    // A fixed number of iterations, each run, rather than as many as fit in a time: the installed
    // arms keep what each call leaves behind, so a run's medians depend on how many calls it made.
    Benchmark.defaultConfiguration = .init(
        metrics: [.wallClock, .cpuTotal, .instructions, .mallocCountTotal],
        warmupIterations: 10,
        maxDuration: .seconds(120),
        maxIterations: 1_000,
        thresholds: [
            .instructions: .init(relative: [.p50: 10.0]),
            .mallocCountTotal: .init(relative: [.p50: 10.0]),
            // Reported, not gated.
            .wallClock: .init(),
            .cpuTotal: .init()
        ]
    )

    // The request the app makes without the drawer: what installing must keep pace with.
    Benchmark(
        "Network: BASELINE URLSession data task, not installed",
        configuration: .init(setup: { try await server.start() })
    ) { benchmark in
        for _ in benchmark.scaledIterations {
            try await blackHole(session.data(from: server.url))
        }
    }

    Benchmark(
        "Network: URLSession data task, installed",
        configuration: .init(setup: {
            try await server.start()
            await MainActor.run { DebugDrawer.shared.installNetwork(sessions: .off) }
            guard URLSessionConfiguration.ephemeral.protocolClasses?.first.map(NSStringFromClass)?.hasSuffix("DebugNetworkProtocol") == true else {
                fatalError("installNetwork() didn't put its URL protocol first in new sessions' configurations")
            }
            _ = session
        })
    ) { benchmark in
        for _ in benchmark.scaledIterations {
            try await blackHole(session.data(from: server.url))
        }
    }
}
