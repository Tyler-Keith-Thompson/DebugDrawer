// What recording performance traces costs the app: the stall monitor's parts, a run loop turn with
// and without the monitor, and a signpost interval with and without a recording. The capability is
// real in every build, so DEBUG (which `just bench` defines) changes nothing measured here.
//
// The checkpoint, the watcher's wake, the stack sampler and the symbolicator are `package` API:
// no public call reaches one alone, so this target is compiled with the library's package name
// (PACKAGE_ACCESS_BENCHMARKS in scripts/modules.py). The run loop turns and the signposts go
// through the public `PerformanceTraces`, as a host's do.
import Benchmark
import CoreFoundation
import DebugDrawerHangDetector
import DebugDrawerReceiver
import Foundation

/// The run loop turns' recorder and its sessions; made on the main actor by the setup of the
/// benchmarks that use them, then kept for the process.
@MainActor var traces: PerformanceTraces?
@MainActor var sessions: DebugDrawerSessions?

/// A thread of its own, parked on a semaphore, whose stack the sampler reads: as the watcher reads
/// the main thread's while it is stuck.
nonisolated(unsafe) var parkedSampler: MachThreadStackSampler?
let parkedRelease = DispatchSemaphore(value: 0)

/// The stack the symbolicator names: this process's, as the setup reads it.
nonisolated(unsafe) var addresses: [UInt] = []

/// Opens a session in which `traces` records, as a sidecar's Start Recording does, and traps unless
/// it records.
@MainActor func startRecording(limits: PerformanceTraces.Limits = .standard) {
    let opened = DebugDrawerSessions(maximumDuration: 3600)
    let recorder = PerformanceTraces(sessions: opened, limits: limits)
    opened.perform(.open(duration: 3600))
    recorder.perform(.start)
    guard recorder.snapshot.isRecording else {
        fatalError("PerformanceTraces didn't start recording in an open session")
    }
    sessions = opened
    traces = recorder
}

/// Turns the main run loop `turns` times, each turn a block that schedules the next and wakes the
/// loop, so every turn waits and is woken as an app's does, and the monitor's observers see each
/// turn's start and its wait. Runs the loop nested in the main actor's job, which it returns to.
@MainActor func turnMainRunLoop(_ turns: Int) {
    let runLoop = CFRunLoopGetMain()!
    nonisolated(unsafe) var remaining = turns
    nonisolated(unsafe) var turn: (() -> Void)?
    turn = {
        remaining -= 1
        if remaining == 0 {
            CFRunLoopStop(runLoop)
        } else {
            CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, turn)
            CFRunLoopWakeUp(runLoop)
        }
    }
    CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, turn)
    CFRunLoopRun()
    turn = nil
}

/// Keeps the main run loop's default mode from being empty, so a nested run waits for the next
/// block rather than returning; added once, by the run loop benchmarks' setup.
@MainActor func keepMainRunLoopAlive() {
    let keepAlive = CFRunLoopTimerCreateWithHandler(nil, .greatestFiniteMagnitude, 0, 0, 0) { _ in }
    CFRunLoopAddTimer(CFRunLoopGetMain(), keepAlive, .defaultMode)
}

let benchmarks: @Sendable () -> Void = {
    // Each benchmark runs in a process of its own, so one benchmark's recording never reaches
    // another. Gated (just bench-check) at 10% over the main baseline's median: the process's
    // retired instructions, every thread's, so the watcher thread's work counts, and its mallocs;
    // reported only: wall clock and CPU time, which move with whatever else the Mac is doing.
    // A thousand calls (or turns) an iteration, reported per call; a fixed number of iterations.
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

    // What the main run loop's observers check at a turn's start and at its wait, with no stall:
    // one of each a call.
    Benchmark("HangDetector: checkpoint pair, no stall") { benchmark in
        let state = HangMonitorState(threshold: PerformanceTraces.defaultHitchThreshold)
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            blackHole(state.checkpoint(isAboutToWait: false))
            blackHole(state.checkpoint(isAboutToWait: true))
        }
    }

    // What the watcher thread does at each wake while the watched thread is waiting.
    Benchmark("HangDetector: watcher wake, thread idle") { benchmark in
        let state = HangMonitorState(threshold: PerformanceTraces.defaultHitchThreshold)
        _ = state.checkpoint(isAboutToWait: true)
        let sampler = MachThreadStackSampler.currentThread()
        benchmark.startMeasurement()
        for _ in benchmark.scaledIterations {
            state.tick(sampler)
        }
    }

    // A main run loop turn that waits and is woken, which the recording must keep pace with.
    Benchmark(
        "HangDetector: BASELINE main run loop turn, not recording",
        configuration: .init(setup: { await MainActor.run { keepMainRunLoopAlive() } })
    ) { benchmark in
        let turns = benchmark.scaledIterations.count
        await MainActor.run { turnMainRunLoop(turns) }
    }

    // The same turn while a sidecar's recording runs: both observers and the watcher thread.
    Benchmark(
        "HangDetector: main run loop turn, recording",
        configuration: .init(setup: {
            await MainActor.run {
                keepMainRunLoopAlive()
                startRecording()
            }
        })
    ) { benchmark in
        let turns = benchmark.scaledIterations.count
        await MainActor.run { turnMainRunLoop(turns) }
    }

    // Reading a stopped thread's stack, as the watcher does once a stall passes the threshold:
    // the stop, the read and the resume. A hundred an iteration, reported per iteration.
    Benchmark(
        "HangDetector: sample a parked thread's stack, 100 times",
        configuration: .init(
            scalingFactor: .one,
            setup: {
                await withCheckedContinuation { ready in
                    Thread {
                        parkedSampler = .currentThread()
                        ready.resume()
                        parkedRelease.wait()
                    }.start()
                }
            },
            teardown: { parkedRelease.signal() }
        )
    ) { benchmark in
        // Set by the setup, which returns only once the thread has made it.
        let sampler = parkedSampler!
        let frames = UnsafeMutableBufferPointer<UInt>.allocate(capacity: HangMonitorState.maximumFrames)
        defer { frames.deallocate() }
        benchmark.startMeasurement()
        for _ in 0 ..< 100 {
            blackHole(sampler.sample(into: frames))
        }
        benchmark.stopMeasurement()
    }

    // Naming every frame of this process's stack, as a stall is recorded; ten stacks an
    // iteration, reported per iteration.
    Benchmark(
        "HangDetector: name a stack's frames, 10 times",
        configuration: .init(
            scalingFactor: .one,
            setup: {
                addresses = Thread.callStackReturnAddresses.map { UInt(truncating: $0) }
                guard !addresses.isEmpty else { fatalError("No stack to name") }
            }
        )
    ) { _ in
        for _ in 0 ..< 10 {
            blackHole(Symbolicator.frames(for: addresses))
        }
    }

    // A signpost interval begun and ended while no sidecar records: what every host pays. On the
    // main actor, as the recording arm's.
    Benchmark(
        "HangDetector: BASELINE signpost interval, nothing recording",
        configuration: .init(setup: {
            await MainActor.run {
                let idle = DebugDrawerSessions(maximumDuration: 3600)
                sessions = idle
                traces = PerformanceTraces(sessions: idle)
            }
        })
    ) { benchmark in
        let intervals = benchmark.scaledIterations.count
        await MainActor.run {
            // Made by the setup.
            let recorder = traces!
            for _ in 0 ..< intervals {
                recorder.endInterval(recorder.beginInterval("Benchmark"))
            }
        }
    }

    // The same interval while a recording runs, with its share of taking the recorded intervals
    // into the snapshot: each iteration ends by collecting them (an export), on the main actor
    // where its intervals were made, so the recorder's own collecting, which the intervals wake
    // on the main actor, finds them taken rather than running for some iterations and not others.
    // The recording keeps a hundred intervals at most and counts the rest as dropped, as a
    // session's would once full.
    Benchmark(
        "HangDetector: signpost interval, recording",
        configuration: .init(setup: {
            await MainActor.run { startRecording(limits: PerformanceTraces.Limits(stalls: 1, intervals: 100)) }
        })
    ) { benchmark in
        let intervals = benchmark.scaledIterations.count
        await MainActor.run {
            // Made by the setup.
            let recorder = traces!
            for _ in 0 ..< intervals {
                recorder.endInterval(recorder.beginInterval("Benchmark"))
            }
            recorder.perform(.export)
        }
    }
}
