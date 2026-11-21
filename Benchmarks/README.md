# Benchmarks

What the drawer costs the host app: each path the Network, DiskIO and Console plugins intercept,
measured not installed (the `BASELINE` entry) and installed, and the per-call and per-turn costs
of the stall monitor, the leak detector, network mocking's URL protocol and the network log's
filter, in one benchmark process each. A separate SwiftPM package built on
[ordo-one/benchmark](https://github.com/ordo-one/benchmark), so no library target depends on the
benchmark framework. Bazel ignores it (`.bazelignore`).

| Command | Does |
|---|---|
| `just bench` | Run every benchmark (`--target X` for one target, `--filter <regex>` for some) |
| `just bench-compare` | Run them and show the difference from the `main` baseline |
| `just bench-check` | The regression gate: exits non-zero when a benchmark regresses past its threshold against `main` |
| `just bench-baseline` | Record the `main` baseline, which is committed |

`Package.swift` is generated from `BENCHMARKS` in `scripts/modules.py`: a row per target, with what
it imports. Add a target there, then `just modules`.

## What is measured

| Target | What is measured |
|---|---|
| `DebugDrawerNetworkPluginBenchmarks` | A `URLSession` data task (GET, small JSON body) to a server on the loopback interface, in-process, not installed (`BASELINE`) and installed; and, over a log of 200 captured JSON responses, parsing and pretty-printing their bodies once (`BASELINE`) against typing six keystrokes into the log's filter |
| `DebugDrawerDiskIOPluginBenchmarks` | `FileManager` `createFile` + `removeItem`, `contents(atPath:)`, `attributesOfItem(atPath:)`, `contentsOfDirectory(atPath:)` in a temporary directory, and `Data` `write(to:)` + `init(contentsOf:)`, which the plugin doesn't intercept |
| `DebugDrawerConsolePluginBenchmarks` | A line written with `FileHandle.standardOutput.write` and with `print`, each read back out of a pipe of the benchmark's own before the next is written (installed, after the plugin forwards it; its main-actor share runs between iterations), and logged with `Logger.notice`; the installed `Logger` arm ends each iteration with the plugin's log-store read, forced |
| `DebugDrawerHangDetectorBenchmarks` | The stall monitor: a pair of run loop checkpoints with no stall, the watcher's wake while the thread waits, sampling a parked thread's stack (100 an iteration), naming a stack's frames (10 stacks an iteration); a main run loop turn that waits and is woken, not recording (`BASELINE`) and while `PerformanceTraces` records, the watcher thread's work included; a signpost interval while nothing records (`BASELINE`) and while recording |
| `DebugDrawerLeakDetectorPluginBenchmarks` | A main run loop turn that waits and is woken, not installed (`BASELINE`), installed with nothing dismissed, and installed with ten dismissed view controllers still alive, flagged and rechecked each turn |
| `DebugDrawerNetworkBenchmarks` | `NetworkMockingURLProtocol.canInit(with:)`, as URL loading asks it: no rules in effect (`BASELINE`), 50 wildcard rules of which the last matches, and the same rules for a host the capability doesn't allow |

The overhead of a path is its installed result minus its `BASELINE`. The DiskIO, Console,
HangDetector, LeakDetector and network-mocking benchmarks make a thousand calls (or run loop
turns) an iteration and report per call (`Instructions (K)` is thousands of instructions per
call), except stack sampling and frame naming, which report per iteration of 100 samples and 10
stacks; the Network data tasks make one request an iteration, and the filter's pair one parse or
six keystrokes. Each runs a fixed number of iterations, so every run makes the same calls: the
installed arms keep what the calls leave behind, and a run of a different length would have
different medians.

Each benchmark runs in a process of its own, so one benchmark's install never reaches another.

The run loop benchmarks turn the main run loop themselves, nested in a main-actor job: each turn
a block that schedules the next and wakes the loop, so every turn waits and is woken, and the
observers see its start and its wait as an app's do.

## Reaching `package` API

A benchmark target sees only what the library's modules make visible to another package. Most
go through public API, as a host does: `PerformanceTraces` for the run loop turns and signposts,
`LeakDetector.install()` and `viewDidDisappear` for the leak detector,
`NetworkMockingURLProtocol.canInit(with:)` for network mocking, `installNetwork` and
`NetworkStore.shared` for the filter. The stall monitor's checkpoint, watcher wake, stack sampler
and symbolicator are `package` declarations no public call reaches alone, so
`DebugDrawerHangDetectorBenchmarks` is compiled with the library's package name
(`PACKAGE_ACCESS_BENCHMARKS` in `scripts/modules.py`, `-package-name` in `Package.swift`, which
works the name out from the library's directory, as SwiftPM does).

## Building: optimized, with DEBUG defined

The interception and the leak detector exist only under `#if DEBUG`; a release build of the
library has no-op stand-ins in their place and would measure nothing. So `just bench` builds the
benchmarks in ordo-one's release configuration (`-O`) and passes `-Xswiftc -DDEBUG` to SwiftPM,
which defines DEBUG for every module in the build, the library's included. Each of those
benchmark sources holds an `#error` under `#if !DEBUG`, so a build without it fails rather than
measuring the stand-ins. The stall monitor and network mocking are capabilities, real in every
build, so DEBUG changes nothing they measure. The benchmarks also check at setup that the install
took (the URL protocol first in new sessions, `FileManager` swizzled, stdout a pipe,
`viewDidDisappear` exchanged, the recording started, the URL protocol claiming the matching
request alone, the filter matching every captured response) and trap otherwise.

DEBUG reaches the dependencies too, where it turns on swift-argument-parser's and swift-system's
debug-only checks; those run in the runner's startup, outside the measured iterations, and both
arms run the same binary.

`--disable-sandbox`: the Network benchmarks listen on the loopback interface and the DiskIO ones
write to the temporary directory, which SwiftPM's plugin sandbox forbids.

## The gate

`just bench-check` runs every benchmark and compares it with the committed `main` baseline
(`.benchmarkBaselines/<Target>/main/results.json`) through ordo-one's `baseline check`. It exits
0 when nothing regressed (improvements alone pass, with a note to re-record), and non-zero
otherwise: when a benchmark regressed past its threshold (the output ends in
`error: benchmarkThresholdRegression`, after a table of each deviation), or when the build or a
benchmark failed. A CI job needs only `just bench-check` on a Mac with Xcode; `--target X` gates
one target.

**Threshold: a benchmark fails the gate when its median (p50) instructions or its median mallocs
rise more than 10% over the `main` baseline's.** Both arms of every path are gated, so a
regression in the interception shows in its installed benchmark, and a change in the machine or
toolchain shows in the `BASELINE` beside it too. The threshold is set for every benchmark of a
target in its `Benchmark.defaultConfiguration`; run to run, these medians move by a few percent
at most, so 10% fails on a real change and not on noise.

- Instructions are the process's retired instructions (`proc_pid_rusage`), every thread's, so they
  include the work interception moves off the calling thread: URLSession's own threads, the
  console's pipe reader, the main-actor records, the hang watcher thread. Mallocs are counted across threads too. Both
  repeat closely from run to run on a busy machine, where time doesn't.
- Wall clock and CPU time are reported, with no threshold: they move with whatever else the Mac
  is doing.
- The baseline belongs to the machine that recorded it (its chip, macOS and Xcode). Record it again
  with `just bench-baseline` on the machine that runs the gate, after a toolchain or OS update,
  and after a change meant to alter the cost, and commit it with that change. Re-record whole
  targets: `--filter` would write a baseline holding only the benchmarks it ran.

### The gate and the Performance tests

The `Performance/` tests of the same paths (`PerformanceTracesOverheadTests`,
`LeakDetectorOverheadTests`, `NetworkMockingRouteSpeedTests`, `NetworkFilterSpeedTests`) stay,
with their bounds: they bound thread CPU time several times over what the path takes, run in
every `just test` and `just test-release`, and catch a path that starts doing real work. They
can't see a 10% change, which moves with the machine's load; the benchmarks count it.

`just test` doesn't run `just bench-check`: the gate needs a baseline recorded on the same Mac,
while it was quiet, and the whole run takes about four minutes (the HangDetector, LeakDetector
and network-mocking targets and the filter's pair add under a minute of it), so a gate run on
every test, on a shared and loaded machine, would fail on the machine rather than on the code.
Run it after a change to a path it measures (AGENTS.md, "What to run"), and in CI on a Mac kept
for it.
