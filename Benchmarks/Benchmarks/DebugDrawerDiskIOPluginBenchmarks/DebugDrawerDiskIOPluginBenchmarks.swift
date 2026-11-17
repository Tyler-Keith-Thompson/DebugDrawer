// The interception measured here exists only in debug builds of the library (`#if DEBUG`), and a
// release build of it has no-op stand-ins, which would measure nothing. `just bench` builds
// optimized with DEBUG defined; this stops any other build from passing for a measurement.
#if !DEBUG
    #error("Build the benchmarks with `just bench`, which defines DEBUG: the interception they measure is DEBUG-only.")
#endif

import Benchmark
import DebugDrawer
import DebugDrawerDiskIOPlugin
import Foundation
import ObjectiveC

/// A directory of this process's own under the temporary directory: one file to read, and a
/// hundred to list.
let directory = FileManager.default.temporaryDirectory.appending(path: "DebugDrawerDiskIOBenchmarks-\(getpid())")
let readPath = directory.appending(path: "read.json").path
let writePath = directory.appending(path: "write.json").path
let writeURL = directory.appending(path: "data.json")
let listedPath = directory.appending(path: "listed").path
let contents = Data(repeating: 0x7B, count: 4096)

/// Creates the directory's files, and installs the plugin when `installed`, after which every
/// FileManager call the plugin swizzles goes through it.
@Sendable func prepare(installed: Bool) async throws {
    try FileManager.default.createDirectory(atPath: listedPath, withIntermediateDirectories: true)
    try contents.write(to: URL(filePath: readPath))
    for index in 0 ..< 100 {
        try contents.write(to: URL(filePath: listedPath).appending(path: "\(index).json"))
    }
    guard installed else { return }
    let read = #selector(FileManager.contents(atPath:))
    let original = class_getInstanceMethod(FileManager.self, read).map(method_getImplementation)
    await MainActor.run { DebugDrawer.shared.installDiskIO() }
    guard class_getInstanceMethod(FileManager.self, read).map(method_getImplementation) != original else {
        fatalError("installDiskIO() didn't swizzle FileManager.contents(atPath:)")
    }
}

@Sendable func cleanUp() async throws {
    try FileManager.default.removeItem(at: directory)
}

let benchmarks: @Sendable () -> Void = {
    // Each benchmark runs in a process of its own, so one benchmark's install never reaches another.
    // Gated (just bench-check) at 10% over the main baseline's median: the process's retired
    // instructions and its mallocs, which repeat from run to run within a few percent;
    // reported only: wall clock and CPU time, which move with whatever else the Mac is doing.
    // A thousand calls an iteration, so the main-actor work each call schedules is spread evenly.
    // A fixed number of iterations, each run, rather than as many as fit in a time: the installed
    // arms keep what each call leaves behind, so a run's medians depend on how many calls it made.
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

    for installed in [false, true] {
        let arm = installed ? "installed" : "not installed"
        // The not-installed call is the BASELINE: what installing must keep pace with.
        let prefix = installed ? "DiskIO:" : "DiskIO: BASELINE"
        let configuration = Benchmark.Configuration(setup: { try await prepare(installed: installed) }, teardown: cleanUp)

        Benchmark("\(prefix) createFile + removeItem, 4 KiB, \(arm)", configuration: configuration) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(FileManager.default.createFile(atPath: writePath, contents: contents))
                try FileManager.default.removeItem(atPath: writePath)
            }
        }

        Benchmark("\(prefix) contents(atPath:), 4 KiB, \(arm)", configuration: configuration) { benchmark in
            for _ in benchmark.scaledIterations {
                blackHole(FileManager.default.contents(atPath: readPath))
            }
        }

        Benchmark("\(prefix) attributesOfItem(atPath:), \(arm)", configuration: configuration) { benchmark in
            for _ in benchmark.scaledIterations {
                try blackHole(FileManager.default.attributesOfItem(atPath: readPath))
            }
        }

        Benchmark("\(prefix) contentsOfDirectory(atPath:), 100 files, \(arm)", configuration: configuration) { benchmark in
            for _ in benchmark.scaledIterations {
                try blackHole(FileManager.default.contentsOfDirectory(atPath: listedPath))
            }
        }

        // Not swizzled: the pair shows installing leaves Data's own file I/O alone.
        Benchmark("\(prefix) Data write(to:) + Data(contentsOf:), 4 KiB, \(arm)", configuration: configuration) { benchmark in
            for _ in benchmark.scaledIterations {
                try contents.write(to: writeURL)
                try blackHole(Data(contentsOf: writeURL))
            }
        }
    }
}
