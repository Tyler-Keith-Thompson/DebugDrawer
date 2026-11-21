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

/// Answers every request with a JSON body of 400 users that starts with `"aaa":"needle"`, so once
/// pretty-printed with sorted keys, every keystroke of "needle" matches near the start of the body.
let feedServer: LoopbackHTTPServer = {
    let users = (0 ..< 400).map { #"{"id":\#($0),"name":"user \#($0)","roles":["reader","writer"],"active":true}"# }
    return LoopbackHTTPServer(body: Data(#"{"aaa":"needle","items":[\#(users.joined(separator: ","))]}"#.utf8))
}()

/// What typing "needle" into the log's filter sends it, a keystroke at a time.
let keystrokes = ["n", "ne", "nee", "need", "needl", "needle"]

/// Installs the plugin, sends 200 requests to `feedServer` (one per page, as the log holds 200),
/// and returns once the log holds all 200, complete; traps unless the whole query, "needle", then
/// matches every one.
@MainActor func capture200Responses() async throws {
    try await feedServer.start()
    DebugDrawer.shared.installNetwork(sessions: .off)
    let captured = URLSession(configuration: .ephemeral)
    for page in 0 ..< 200 {
        var components = URLComponents(url: feedServer.url, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "page", value: "\(page)")]
        // Trap: the server's URL with a query item of digits always forms a URL.
        _ = try await captured.data(from: components!.url!)
    }
    let store = NetworkStore.shared
    for await entries in store.$entries.values where entries.count == 200 && entries.allSatisfy(\.isComplete) {
        break
    }
    store.filterText = "needle"
    guard store.filteredEntries.count == 200 else {
        fatalError("The filter didn't match every captured response")
    }
    store.filterText = ""
}

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

    // The log's filter runs on the main thread at every keystroke, over every request the log
    // holds; measured against the work it must not repeat, parsing and pretty-printing the 200
    // bodies once. A filter that searches the text worked out as each body arrived takes a small
    // share of one parse; one that parses each body takes six parses or more. Both read the same
    // log of 200 captured responses; an iteration is one parse, or six keystrokes.
    let filterConfiguration = Benchmark.Configuration(
        warmupIterations: 2, maxIterations: 20, setup: { try await capture200Responses() }
    )

    Benchmark("Network: BASELINE parse 200 captured JSON response bodies once", configuration: filterConfiguration) { _ in
        await MainActor.run {
            for entry in NetworkStore.shared.entries {
                blackHole(entry.prettyResponseBody?.lowercased())
            }
        }
    }

    Benchmark("Network: filter 200 captured JSON responses, six keystrokes", configuration: filterConfiguration) { _ in
        await MainActor.run {
            let store = NetworkStore.shared
            for query in keystrokes {
                store.filterText = query
                blackHole(store.filteredEntries.count)
            }
        }
    }
}
