# Benchmarks

What the drawer's interception costs the host app: each path the Network, DiskIO and Console
plugins intercept, measured not installed (the `BASELINE` entry) and installed, in one benchmark
process each. A separate SwiftPM package built on
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

| Target | Paths, each not installed and installed |
|---|---|
| `DebugDrawerNetworkPluginBenchmarks` | A `URLSession` data task (GET, small JSON body) to a server on the loopback interface, in-process |
| `DebugDrawerDiskIOPluginBenchmarks` | `FileManager` `createFile` + `removeItem`, `contents(atPath:)`, `attributesOfItem(atPath:)`, `contentsOfDirectory(atPath:)` in a temporary directory, and `Data` `write(to:)` + `init(contentsOf:)`, which the plugin doesn't intercept |
| `DebugDrawerConsolePluginBenchmarks` | A line written with `FileHandle.standardOutput.write` and with `print`, each read back out of a pipe of the benchmark's own before the next is written (installed, after the plugin forwards it; its main-actor share runs between iterations), and logged with `Logger.notice`; the installed `Logger` arm ends each iteration with the plugin's log-store read, forced |

The overhead of a path is its installed result minus its `BASELINE`. The DiskIO and Console
benchmarks make a thousand calls an iteration and report per call (`Instructions (K)` is
thousands of instructions per call); the Network ones make one request an iteration. Each runs a
fixed number of iterations, so every run makes the same calls: the installed arms keep what the
calls leave behind, and a run of a different length would have different medians.

Each benchmark runs in a process of its own, so one benchmark's install never reaches another.

## Building: optimized, with DEBUG defined

The interception exists only under `#if DEBUG`; a release build of the library has no-op stand-ins
in its place and would measure nothing. So `just bench` builds the benchmarks in ordo-one's
release configuration (`-O`) and passes `-Xswiftc -DDEBUG` to SwiftPM, which defines DEBUG for
every module in the build, the library's included. Each benchmark source holds an `#error` under
`#if !DEBUG`, so a build without it fails rather than measuring the stand-ins. The benchmarks also
check at setup that the install took (the URL protocol first in new sessions, `FileManager`
swizzled, stdout a pipe) and trap otherwise.

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
  console's pipe reader, the main-actor records. Mallocs are counted across threads too. Both
  repeat closely from run to run on a busy machine, where time doesn't.
- Wall clock and CPU time are reported, with no threshold: they move with whatever else the Mac
  is doing.
- The baseline belongs to the machine that recorded it (its chip, macOS and Xcode). Record it again
  with `just bench-baseline` on the machine that runs the gate, after a toolchain or OS update,
  and after a change meant to alter the cost, and commit it with that change. Re-record whole
  targets: `--filter` would write a baseline holding only the benchmarks it ran.
