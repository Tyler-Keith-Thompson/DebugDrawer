# DebugDrawer: notes for coding agents

DebugDrawer is a plugin-based debug drawer for apps on Apple platforms: a slide-in panel where each
debugging tool is its own library, so an app links only the tools it wants. It is for developers
and internal testers of their own app, on macOS and iOS today, and optimizes for costing nothing in
what ships to end users: release builds get no-op stand-ins. The board's charter
(`.kanban/triage.md`) says what is in scope and the rules a change must fit. Swift 6.3 (minimum).
Bazel is the development build; SwiftPM is the published package. `README.md` is the user-facing
overview.

This file came from a project template. Sections marked *default* describe how the owner likes
every project built; delete a rule only when it cannot apply here, and say so in the commit.

## Layout

```
Sources/<Module>/                One directory per module, each with a generated BUILD.bazel
Sources/DebugDrawer/             The core module: the drawer, the plugin protocol and registry (no umbrella)
Sources/DebugDrawer<Name>Plugin/ One module per shipped plugin
Tests/<Module>Tests/             One test target per module; Performance/ holds speed-reliant tests
Tests/DebugDrawerTests/          The core's tests and the README examples, verbatim
Tests/DebugDrawerTestSupport/    Shared test fixtures (data only)
Tests/DebugDrawerInterceptionContract/  The interception contract's checks (TEST_HELPERS), test-only
Example/                         The macOS, iOS, visionOS, tvOS and watchOS example apps, a UIKit-only and an
                                 AppKit-only one, a sidecar (Sidecar) and the production host it drives (Receiver)
                                 for iOS and macOS, and the libraries they share: TestBench (actions that give each
                                 plugin data) and Plugins (every plugin with its defaults) (hand-written BUILD.bazel)
Benchmarks/                      The benchmarks (interception, the stall monitor, the leak detector, network mocking, the
                                 network log's filter): a SwiftPM package of its own (ordo-one/benchmark),
                                 generated from BENCHMARKS, with the committed main baseline (Benchmarks/README.md)
scripts/modules.py               The module graph
scripts/catalyst_example.py      The iOS example as a Mac Catalyst app: a SwiftPM package derived from Example's sources
scripts/test_skips.py            SKIP_TESTS as each SwiftPM test runner takes it (swift test's --skip, xcodebuild's -skip-testing:)
scripts/xcode_cache.py           The settings with which every xcodebuild recipe shares compile results between checkouts
                                 (Xcode's compilation caching, in ~/Library/Caches/debugdrawer-xcode-cas)
scripts/release.py               The release gates `just deploy` runs (changelog entry, API breaks)
scripts/sign_example.py          Re-signs the Mac example `just run` installs with the Keychain's Apple Development identity
tools/                           Bazel rule wrappers (warnings as errors, Swift 6 mode), DocC rules;
                                 tools/bazel turns BuildBuddy on when the Keychain holds its key, and
                                 on macOS sweeps stale output bases once a day (tools/sweep-output-bases):
                                 a deleted workspace's, or one idle 7 days
tools/test_host/                 The app the iOS simulator tests (`TESTED_PLATFORMS["iOS"]`) run inside, whose
                                 entitlements give the Keychain and App State Reset tests a keychain
tools/lint.bzl                   `just lint`: SwiftLint (.swiftlint.yml) and a11y-check over first-party targets
```

### Module graph

`scripts/modules.py` is the source of truth for modules, their dependencies, test targets,
external packages and platforms. `just modules` regenerates `Package.swift`, every `BUILD.bazel`,
the umbrella module and `swift/Package.swift` from it. Never edit the generated files by hand;
`//:package_swift_test` fails when `Package.swift` disagrees with the Bazel graph.
`just modules` refuses a table or function defined twice in it, which a template update can merge
in beside the project's own: keep one definition, holding the project's rows, and delete the other.

- Add a module: a row in `MODULES` (name, group, description, dependencies), then `just modules`.
- Add a test target: a row in `TEST_TARGETS`. A target with a `Performance/` directory of Swift
  sources must be listed in `PERFORMANCE_TESTS`, and the reverse.
- Add a test helper (shared checks several test targets run): a row in `TEST_HELPERS`. It is a
  testonly library visible only to `//Tests/...`, which no module may list.
- Run a test target in the iOS simulator as well: a row in `TESTED_PLATFORMS["iOS"]`, then
  `just modules`. It runs through `//tools:ios_test_runner` in a new simulator, hosted by
  `tools/test_host`, without the packages `BAZEL_TESTED_PLATFORM_EXCLUDED_PACKAGES` names. Leave
  the template's `SIMULATOR_TESTS` empty: its runner links every Apple-only package and has no
  such exclusions. The iOS apps are the hand-written ones under `Example/`, so the template's
  `--ios` option doesn't apply.
- Give a test target an environment variable under `bazel test` (an integration test that runs
  only when `TEST_DATABASE_URL` is set, say): its name and the variables in `TEST_ENVIRONMENT`
  (`{"<Target>Tests": ["TEST_DATABASE_URL"]}`), then `just modules`. Bazel strips the test
  environment; the generator writes the names as `env_inherit` on that target's `swift_test`, its
  Performance one and its simulator `ios_unit_test`, so only those targets see the variable and
  only their cached results depend on it. Not `--test_env` in `.bazelrc`, which hands it to every
  test. SwiftPM passes the whole environment already. `check()` refuses a name that isn't a test
  target.
- Add an executable: a row in `EXECUTABLES` (name, description, dependencies). It holds only
  `@main`; its code lives in a module, where tests reach it.
- Add a dynamic library (C code that must be an image of its own, loaded at launch, such as
  `DebugDrawerDiskIOInterposer`'s dyld interposing tuples): a row in `DYNAMIC_LIBRARIES`. It is a
  `.dynamic` product in SwiftPM and a dylib in Bazel; only test targets and apps link it, and a
  module that uses it finds its functions with `dlsym`.
- Add an example module (a demo app's views, a sample server's routes): a row in `MODULES` and its
  name in `EXAMPLE_MODULES`, then `just modules`. It builds and tests like any module, but has no
  library product, umbrella import or DocC archive, so neither it nor its dependencies ship. Only
  executables, test targets and other example modules may depend on it (`check()` enforces it).
- Offer a module on its own but not through `import DebugDrawer` (a test-support back end, such as
  an in-memory store adopters use in their tests): its name in `NON_UMBRELLA_MODULES` too, then
  `just modules`. It keeps its library product and DocC archive; only the umbrella leaves it out.
  The umbrella catalog's topic list is hand-written: list it there under a heading of its own, not
  among the production modules.
- A library module that imports Swift Testing (a helper adopters add to their test targets: a
  custom `Trait`, an assertion that records an `Issue`): its name in `TESTING_MODULES` and
  `NON_UMBRELLA_MODULES` too, then `just modules`. Bazel finds Testing only on the developer search
  paths, which rules_swift gives testonly targets alone; the generator gives them to its
  `swift_library` and its docs' symbol graph. A module that depends on it must be listed too, and no
  executable may (`check()` enforces both).
- Give a module resources (data files, Apple's privacy manifest): put them under `Sources/<Module>/`
  and list each in `RESOURCES` (`{"<Module>": [("process", "Data/x.json"), ("copy", "Fixtures")]}`,
  paths relative to the module, rules as SwiftPM's `.process` and `.copy`), then `just modules`.
  Package.swift gets `resources:`, and Bazel the same `DebugDrawer_<Module>.bundle`
  (`tools/resources.bzl`): nested in an app's or test bundle's resources on Apple platforms, in the
  runfiles of `bazel test` and `bazel run` on macOS and Linux, found by a generated `Bundle.module`.
  The module reads them through `Bundle.module` under either build system, and its tests read them
  through the module. Bazel processes `process` files only inside Apple bundles (strings, asset
  catalogs); elsewhere they are copied as they are, as SwiftPM does off Apple platforms. A module
  that calls a required-reason API or collects data ships `PrivacyInfo.xcprivacy`, listed as
  `("copy", "PrivacyInfo.xcprivacy")` so it sits at the bundle's root; `check()` refuses one left
  out, a listed path that doesn't exist, and one inside another listed directory.
- Give a test target fixture files (JSON to compare byte for byte, a sample input): put them under
  `Tests/<Target>/` and list them in `RESOURCES` under the target's name
  (`{"<Target>": [("copy", "Fixtures")]}`, paths relative to `Tests/<Target>`), then `just modules`.
  The target gets its own `DebugDrawer_<Target>.bundle` the same way, in its swift_test, its
  simulator ios_unit_test and its SwiftPM test target, and its tests read the files through
  `Bundle.module`. Not under `Performance/`, which the target leaves out: the speed-reliant tests
  of a `PERFORMANCE_TESTS` target list theirs under `<X>PerformanceTests`, paths relative to
  `Tests/<X>/Performance`, and read them through `Bundle.module` in debug and release alike.
- Add a command plugin (`swift package <verb>`): a row in `PLUGINS` (name, verb, description, and
  the reason it writes to the package directory, or `None` when it writes nothing there), its
  sources in `Plugins/<name>/` (an `@main` `CommandPlugin`), then `just modules`. Package.swift gets
  a `.plugin` target and product; Bazel builds none of it, so no test reaches the plugin. Keep it
  thin, its logic in a module or an executable it builds and runs, and run it on the package
  (`swift package --allow-writing-to-package-directory <verb>`) after a change to it.
- Add an external package: a row in `PACKAGES`, its `swiftpkg_<identity>` repository in
  `MODULE.bazel`'s `use_repo`, then `just modules` and `just resolve`.
- A package whose main module takes the project's name (`import DebugDrawer` is the library
  itself) lists it in `MODULES`; the generator then writes no umbrella.
- A package only Apple platforms build (Objective-C, a wrapper of an Apple framework) goes in
  `APPLE_ONLY_PACKAGES` too: its products are linked on Apple platforms only, so the targets still
  build on Linux, and the code that uses them sits under `#if canImport(...)`.
- A module that builds on a platform where one of its dependencies doesn't (the sidecar kit on
  watchOS, without Console, Network and the Hang Detector): list the dependency for it in
  `PLATFORM_CONDITIONAL_DEPENDENCIES`. Package.swift then links it with `.target(name:condition:)`
  and Bazel in a `select`, on the platforms that build it, and the code that uses it sits under
  `#if canImport(...)`. Xcode builds a package target's whole dependency closure and filters only
  edges that carry a condition, so the generator also conditions that dependency's own
  dependencies that don't build there (`closure_conditions()`: the Console plugin's OSLogClient,
  the Network plugin's DebugDrawerNetwork), on the dependency's platforms.
- Raise the Swift floor (a dependency's manifest needs a newer Swift): set `SWIFT` (every
  manifest's tools version, CI's and the Docker image's Swift, the minimum the docs state) and
  `SWIFT_TOOLCHAIN` (the swift.org release swiftly installs where Xcode's toolchain falls short)
  in `scripts/modules.py`, then `just modules`. It writes them into the generated manifests and
  replaces the previous ones in every other file that names them (`SWIFT_SITES`), from the record
  in `tools/swift_version.bzl`. Never edit a version in those files by hand. `just template-update`
  keeps the project's versions, and says when the template's have passed them.
- A module name takes a `Module` suffix only when it would otherwise equal its main type's name
  (`GreetingModule` would hold `Greeting`). No catch-all modules ("Core", "Utilities").

## Commands

Every shell command gets a timeout. macOS has no `timeout`; use
`perl -e 'alarm 1800; exec @ARGV' <command>`. A bug can make a loop run forever.

| Command | Does |
|---|---|
| `just build` / `just test` | Lint, then build / test everything (debug) |
| `bazel test //Tests/XTests` | One test target (`just test-one //Tests/XTests`) |
| `just filter <pattern>` | Tests whose name matches |
| `just test-release` | `--config=release`: builds and runs only the `XPerformanceTests` targets |
| `just release-check` | Example apps built optimized, and every public symbol present in release (`scripts/release_api.py`); a `just deploy` gate |
| `just spm-visionos-test`, `just spm-tvos-test`, `just spm-watchos-test` | Core's tests (`TESTED_PLATFORMS`) through SwiftPM in that platform's simulator (`VISIONOS_DESTINATION`, `TVOS_DESTINATION`, `WATCHOS_DESTINATION` override it), through a scheme holding only that test target; `just spm-test` runs each. Bazel runs them as `//Tests/DebugDrawerTests:DebugDrawerTests_<platform>` in a new simulator (`tools/simulator_test_runner.bzl`). Bazel has no Catalyst platform (rules_apple has no Catalyst rules, and `--apple_platform_type=catalyst` crashes analysis), so `tools/catalyst.bzl` builds macOS configurations with the Catalyst target triple: `catalyst_build_test` compiles each `CATALYST_MODULES` library, and `catalyst_test` builds a `CATALYST_TESTS` target's swift_test as a Mac Catalyst executable and runs it on the Mac (`//Tests/DebugDrawerTests:DebugDrawerTests_macCatalyst`), without the packages that don't build there (SnapshotTesting; its tests sit under `#if canImport(SnapshotTesting)`). `just spm-catalyst-test` runs every test target for Catalyst |
| `just spm-catalyst-test` | Every test target through SwiftPM for Mac Catalyst (`xcodebuild test -scheme DebugDrawer-Package`), so `targetEnvironment(macCatalyst)` branches run; `just spm-test` runs it. Snapshot tests sit under `#if os(iOS) && !targetEnvironment(macCatalyst)`, as SnapshotTesting doesn't compile there, and so does a test that makes a UIKit window: xctest has no NSApplication |
| `just spm-catalyst-example` | Build the iOS example as a Mac Catalyst app without launching it: every `Example/iOS` file, the example libraries and products their imports name; `just spm` runs it |
| `just spm-test`, `just verify` | SwiftPM tests; both build systems. The Mac's run (`just spm-test-mac`) and Catalyst's get a temporary home folder (`CFFIXED_USER_HOME`), as every Bazel `swift_test` does (`tools/swift_rules.bzl`), so no test writes into `~/Library`: files under the home folder move there, and UserDefaults suites named by `temporarySuiteName(_:)` (below) keep theirs in it. SwiftPM builds the `XPerformanceTests` targets in debug but runs none of them, in any stage or in `just test-ios`: `swift test --skip` and `-skip-testing:` from `scripts/modules.py` (`PERFORMANCE_TESTS`); Bazel runs them. To leave a test out of every stage, and out of `just test-ios`, name it in `SKIP_TESTS` (`SKIP_TESTS="Target/Suite/test(),Target/Suite" just spm-test`): entries take xcodebuild's `-skip-testing:` form, a Swift Testing test with its parentheses and argument labels, and `scripts/test_skips.py` writes the `--skip` regexes swift test takes; a `--skip` argument reaches swift test only |
| `just test-ios` | Every SwiftPM test target on an iOS simulator (the Dynamic Type snapshots) through `xcodebuild test`. Each checkout gets a simulator of its own, an iPad Pro 13-inch (M5) on the newest iOS runtime named `DebugDrawer test-ios: <checkout path>`, made on first use and reused (`scripts/ios_simulator.py`), so two worktrees can run it at once; `IOS_DESTINATION` overrides it, and `SKIP_TESTS` leaves tests out as in `just spm-test`. `just ios-simulator-delete` deletes this checkout's before you remove its worktree, `just ios-simulator-prune` those of checkouts already gone |
| `just modules` | Regenerate build files from `scripts/modules.py` |
| `just resolve` | Re-resolve Bazel's SwiftPM dependencies after editing `PACKAGES` |
| `just docs` | Combined DocC site into `.build/docs` |
| `just generate` | Xcode project from the Bazel graph, written to `xcode/DebugDrawer.xcodeproj` (gitignored) and opened; `--no-open` skips opening it. Never at the root: xcodebuild run beside a `.xcodeproj` builds it instead of `Package.swift`, so every SwiftPM recipe that calls xcodebuild would fail |
| `just run [macOS\|iOS\|appkit\|uikit\|sidecar\|catalyst\|visionOS\|tvOS\|watchOS]` | Build and launch an example app (`catalyst`: the iOS one as a Mac Catalyst app, through SwiftPM; `sidecar [iOS\|macOS]`: Example/Sidecar beside the production host Example/Receiver, in the simulator `IOS_DEVICE` or on the Mac, where `scripts/sign_example.py --app-group` signs both into the signing team's group, or ad hoc into none, and they share a folder in Caches); `-RunTestBench all` runs the test bench at launch. `macOS` installs at `/tmp/debugdrawer-example` and signs with the Keychain's Apple Development identity (`scripts/sign_example.py`; `DEBUGDRAWER_SIGN_IDENTITY` overrides it, `-` for ad hoc, with a warning), so privacy grants survive a rebuild |
| `just run device [args]` | The iOS example on a paired iPhone or iPad (iOS 26+ for what only a device does, such as `BGContinuedProcessingTask`): `scripts/device_example.py` checks for a reachable device (`DEBUGDRAWER_DEVICE` picks one by name or UDID) and the profile, naming what is missing; then a build in an output base of its own (`--config=device`, which signs with `local_provisioning_profile` and `Example/iOS/ExampleApp_iOS_device.entitlements`), installed and launched by `xcrun devicectl`, with `args` passed to the app. One-time setup, in the owner's developer account: Xcode's automatic signing must have made "iOS Team Provisioning Profile: com.debugdrawer.example.ios" with push and the app group `group.com.debugdrawer.example` (the script's error gives the steps) |
| `just deploy [patch\|minor\|major] [allow-breaking] [dry-run]` | Check the release gates, verify, then tag, push the tag and create the GitHub release (the owner's call); `dry-run` runs only the gates |
| `just buildbuddy-key` | Store the BuildBuddy key in the Keychain (once per Mac; builds then use the remote cache) |
| `just template-update` | Merge the project template's changes since `.template.json`'s commit; resolve conflicts, then `just modules`, `just test` |
| `just lint` | SwiftLint and a11y-check over every first-party target; `just test` runs it first |
| `just record-snapshots` | Re-record every snapshot reference (through SwiftPM) after a change to how a view looks |
| `just bench [--target X]` | The benchmarks: Network, DiskIO and Console interception, installed against not installed; the stall monitor's, the leak detector's and network mocking's costs per call and per run loop turn; the network log's filter against one parse of its bodies; `just bench-compare` against the `main` baseline |
| `just bench-check` | The regression gate for CI: fails when a benchmark's instructions or mallocs regress past its threshold against the committed `main` baseline; `just bench-baseline` re-records it (Benchmarks/README.md). Not part of `just test`: the counts need a quiet machine and a baseline from the same Mac |
| `bazel query 'rdeps(//Tests/..., //Sources/X)'` | Test targets affected by a change to X |

- `just deploy` first runs the release gates (`scripts/release.py`, tested by
  `//scripts:release_test`): `CHANGELOG.md` must have a `## [X.Y.Z]` entry for the new version
  (rename Unreleased and commit before deploying), and `swift package diagnose-api-breaking-changes`
  against the last tag must find no break unless the bump is major or `allow-breaking` is given.
  The entry, plus any breaks allowed, becomes the GitHub release's notes.
- Debug is the default configuration. Every test target except the `XPerformanceTests` ones is
  tagged `debug-only`, which `--config=release` filters out.
- A test that bounds wall-clock time, or runs a large input under `.timeLimit`, belongs in
  `Tests/X/Performance/`.
- Release builds use their own output base (see the justfile). Don't create other output bases
  or copies of the repo, and shut down any extra Bazel server you start.
- Run suites through Bazel, not `swift test --filter`.
- First-party warnings are errors (`tools/swift_rules.bzl`); dependencies build quietly. Fix the
  warning, never suppress it. DocC's are too: `just docs` fails on a link that doesn't resolve.
- Exit tests (`#expect(processExitsWith:)`) go in files of their own, apart from the other tests:
  builds for platforms that cannot start a child process (iOS, visionOS, tvOS, watchOS) leave
  those files out.

## DebugDrawer

The charter's rules (`.kanban/triage.md`, "Rules a request must fit"), which take precedence over
the *default* sections below where they differ:

- **No dependency-injection framework, Mockable or other macro package in any library target**,
  so a host app that already has its own DI never ends up with two. This replaces the defaults'
  `@Mockable` protocols, `Factory` registrations and `withTestContainer`: a plugin's services
  (system calls, storage, network, interception, clocks) are plain protocols passed in through
  initializers or an install-time parameter, with a default implementation, and tests use
  hand-written fakes of them. Test targets may use ViewInspector and SnapshotTesting.
- **Core `DebugDrawer` has no package dependencies.** A plugin depends only on core and Apple
  frameworks; OSLogClient for Console is the one exception. A new third-party package must say
  why Apple's framework can't do the job.
- **Vertical modules.** Each plugin is its own product and Bazel target, buildable and testable
  alone. No shared "Utilities" or "Common" target: a helper lives in the plugin that needs it, or
  in core only if it's part of the plugin contract. A new tool is a new plugin, never a feature
  folded into another.
- **Nothing reaches end-user builds.** Every drawer entry point is under `#if DEBUG`, and every
  public API keeps a stand-in so callers compile unchanged in release. Swizzling and interception
  (DiskIO, Network, render tracking, Location) are installed only as a drawer installs the plugin
  (`install(in:)`, which its `install*()` call leads to), and its `uninstall(from:)` puts back each
  original implementation it replaced (`MethodReplacements`, copied into each plugin that swizzles).
  An interception plugin keeps the contract in `WritingPlugins.md` (idempotent, reversible, no
  change in what the app sees, bounded capture, the drawer's own activity left out), and its test
  target runs the `DebugDrawerInterceptionContract` checks.
- **No timing hacks.** No `DispatchQueue.asyncAfter` or `Task.sleep` to wait for some other event;
  use events (Combine, callbacks, notifications, `onAppear`).
- **SwiftUI first.** AppKit or UIKit only where SwiftUI can't do it (swizzling, URLProtocol,
  window capture, hosting the drawer in an AppKit- or UIKit-only app).
- **Platforms.** A plugin works on every supported platform where its API exists; macOS and iOS
  are the platforms built today (`PLATFORMS` in `scripts/modules.py`). Core also builds for
  visionOS, tvOS and watchOS (`EXTRA_PLATFORMS`): a plugin ported to one joins its list, and
  `just build` and `just build-spm` then build it for that platform's simulator. Core's tests also
  run on visionOS, tvOS and watchOS, and the sidecar kit's on watchOS (`TESTED_PLATFORMS`): a test that can't run there
  (ViewInspector and SnapshotTesting don't build for visionOS,
  `APPLE_ONLY_PACKAGE_EXCLUDED_PLATFORMS`; tvOS binds no keyboard shortcut; watchOS has no panel)
  sits under an `#if` that says why. The Keychain and App State Reset tests also run in the iOS simulator under
  `just test`, hosted by `//tools/test_host`, whose entitlements give them the keychain no Mac
  test runner has; a test of the real keychain sits under `#if os(iOS) &&
  targetEnvironment(simulator)` and never touches the Mac's. On tvOS a view is
  driven by focus: no pasteboard, keyboard shortcuts or drag, and Menu (`onExitCommand`) closes
  what is open. On watchOS the drawer is a full-screen list that navigates to each plugin's view
  (`DrawerWatchList`), so a plugin's body is a short column; there is no pasteboard, keyboard,
  context menu or text selection. Core also builds for Mac Catalyst (`CATALYST_MODULES`), and its tests run there under `just test`
  (`CATALYST_TESTS`), where `os(iOS)` holds in a Mac window: an `os(iOS)` branch either adds a
  `targetEnvironment(macCatalyst)` case or says in a comment why the iOS path is right there.
- A test's UserDefaults suite is named by `temporarySuiteName(_:)` (`DebugDrawerTestSupport`): an
  absolute path in the run's home folder, so its file goes with that folder. A plain name keeps its
  file in `~/Library/Preferences` for good: `CFFIXED_USER_HOME` doesn't move it,
  `removePersistentDomain(forName:)` leaves the file, and the preferences daemon writes a file a
  test deletes again some seconds later. Exit tests hand the name to the child.
- View tests use ViewInspector. Get-only accessibility environment keys need a hosted probe
  (`ViewHosting` and `Inspection`), not an offline `inspect()`.
- The example apps under `Example/` are not in the module graph; `bazel build //...` builds them,
  and `just run` launches them.

## Views

Every plugin, and the core drawer, holds SwiftUI views. They live in the plugin's own module
(`AppInfoFactsView` in `DebugDrawerAppInfoPlugin`), built for macOS by Bazel and for macOS and
iOS by SwiftPM.

- **Debug builds only.** View code sits under `#if DEBUG` with the plugin, and the public API keeps
  its release stand-in (`## DebugDrawer`). Tests of views sit under `#if os(macOS)`: they run on
  the Mac. The view-test packages (ViewInspector, SnapshotTesting, IssueReporting) are in
  `APPLE_ONLY_PACKAGES` and are linked by test targets only.
- **A view is a function of its input.** It takes values (`AppInfoFactsView(facts:refresh:)` takes
  an `AppInfoFacts` and a closure), keeps what it changes itself in `@State`, and holds no
  services: a view that needs one takes a closure or a value from the caller. A plugin's top-level
  view reads its shared store or monitor and hands values to inner views like that one; tests
  render the inner views with fixtures. When a view can show several things, its state is one
  enum with a case per thing (Seams and composition).
- **View tests** use ViewInspector on the Mac: `inspect()` a value-taking view, act on what it
  finds (`tap`, `setInput`), then check what it shows. Get-only accessibility environment keys
  need a hosted probe: a probe view defined in the test target, carrying its own `Inspection`,
  hosted with `ViewHosting.host` under the modifier being tested. A view whose own `@State`
  a test must change (a reveal toggle, say) uses ViewInspector's hook, approach #2 of its guide:
  it holds `let inspection = Inspection<Self>()` (the module's internal `Inspection`) and ends
  its body with `.onReceive(inspection.notice) { inspection.visit(self, $0) }`; the test target
  conforms `Inspection` to `InspectionEmissary`, hosts the view with `ViewHosting.host(sut) { }`
  and acts through `sut.inspection.inspect { }`.
- **Snapshot tests** pin how each state renders, in light and dark, with fixture values rather than
  shared or persisted state: `ImageRenderer` draws the view in the color scheme the test sets, and
  `assertSnapshot` compares it with the reference in `__Snapshots__` beside the test (Bazel puts
  them in the test's runfiles). macOS doesn't scale text with Dynamic Type, so the Mac pins no
  Dynamic Type sizes. `ImageRenderer` draws SwiftUI's own views; an AppKit-backed control (a text
  field, picker, switch, disclosure group or `NSViewRepresentable`) renders as a placeholder, so
  host that view in an `NSHostingView` in a window that is never shown, set its `appearance`, and
  draw it into a bitmap at a fixed 2x scale. On iOS it draws every UIKit-backed control (text
  field, picker, switch, segmented control) as a placeholder too, so the iOS Dynamic Type
  snapshots host every view in a `UIHostingController` in a window that is never shown, with no
  safe area, size it with `sizeThatFits`, lay it out with `layoutIfNeeded` and render its layer
  at a fixed 2x scale. `drawHierarchy` draws nothing there: the SwiftPM test runner connects no
  window scene. A snapshot is worth only what a person reads in it,
  so look at every recorded image before committing it. After a change to how a view looks,
  `just record-snapshots`, then review the changed images in `git diff`.
- **Accessibility**: every control has an `accessibilityLabel`; an image that only decorates is
  `accessibilityHidden(true)`; rows that read as one item combine (`.accessibilityElement(children:
  .combine)`); animations respect `accessibilityReduceMotion`; sizes that should grow with text use
  `@ScaledMetric`, and fonts are text styles (`.title`), never fixed sizes. `just lint` runs
  a11y-check over the views.
- `just lint` (SwiftLint, `--strict`, `.swiftlint.yml` plus `.swiftlint-tests.yml` for tests) must
  pass, and `just build` and `just test` run it first; fix the code rather than disable a rule
  inline.

## Building blocks

The owner's own libraries, first in line under "Don't reinvent the wheel" (House rules). Reach
for them before writing a graph, a container or an operator chain by hand, and before adding a
third-party package for the same job. Add one as a row in `PACKAGES` (`scripts/modules.py`) under its
identity, the repository's name in lowercase (`swiftprng`), and list a product among a module's
dependencies as `"<identity>/<Product>"` (`"swiftprng/Generators"`), as the rows below spell them.

| Library | What it is | Use it for |
|---|---|---|
| [Grafluent](https://github.com/Tyler-Keith-Thompson/Grafluent) | A generic, high-performance graph library: copy-on-write representations (`AdjacencyList`, `CompressedSparseRow`, `AdjacencyMatrix`, pseudographs, stable graphs), graph classes with invariants (`DirectedAcyclicGraph`, `BipartiteGraph`, `Tree`) and algorithms (traversal, shortest paths, flows, matching, connectivity, isomorphism, layout) | Anything shaped like a graph or DAG: dependency orderings, scheduling, routing, state machines, reachability. Products are per module (`"grafluent/ShortestPaths"`); the umbrella is `grafluent/Grafluent`. |
| [GrafluentCollections](https://github.com/Tyler-Keith-Thompson/GrafluentCollections) | Graph-shaped collections as copy-on-write values with the standard library's and swift-collections' API shape: balanced search trees (`AVLTree`/`AVLDictionary`, `RedBlackTree`, `Treap`, `SplayTree`) and `FenwickTree` so far; tries, suffix structures, decision diagrams, B-trees, segment, interval and spatial trees, ropes, persistent trees and an LRU cache planned. Tree- and graph-shaped ones convert to the matching Grafluent type | Sorted sets and dictionaries that take inserts and removals, prefix and range sums with updates; check its backlog before hand-writing a planned structure. Products are per module (`"grafluentcollections/BinarySearchTrees"`); the umbrella is `grafluentcollections/GrafluentCollections`. |
| [SwiftPRNG](https://github.com/Tyler-Keith-Thompson/SwiftPRNG) | Seeded random numbers that reproduce bit for bit on every platform and Swift release: generators as values (`Xoshiro256StarStar`, `Xoroshiro128Plus`, `SplitMix64`, with `jump()` for streams that never overlap), platform-stable draws (`uniform(in:)`, `integer(in:)`, `bernoulli(_:)`, with `checked` spellings), `SeedTree` (a seed per named decision, so adding a draw shifts nothing elsewhere, with overrides and `fitting` to search one subtree for a seed that meets a predicate) and `SeedSearch` (the smallest matching seed, concurrently) | Every seeded test, and any program whose randomness must replay: simulations, procedural generation, games, sampling. Never hand-write a generator. `Xoroshiro128Plus(seed:)` gives the same numbers as a hand-written `SeededRandomNumberGenerator` (xoroshiro128+ seeded by SplitMix64), so replacing one changes no pinned value. Products are per module (`"swiftprng/Generators"`: `Generators`, `Sampling`, `SeedTrees`, `SeedDiscovery`); the umbrella is `swiftprng/SwiftPRNG`. |
| [DependencyInjection](https://github.com/Tyler-Keith-Thompson/DependencyInjection) | Swift 6 dependency injection: `Factory` values on `Container`, `@Injected` / `@LazyInjected` / `@ConstructorInjected`, unique, cached and shared scopes, hierarchical containers, and `withTestContainer` so concurrent tests never share state | Any seam a test needs to replace (clocks, network, storage). Tests wrap their body in `withTestContainer { }` and register doubles there. Product `"dependencyinjection/DependencyInjection"`. |
| [Afluent](https://github.com/Tyler-Keith-Thompson/Afluent) | Reactive operators over async/await: `DeferredTask` (a unit of work that yields one value) and `AsyncSequence` extensions with Combine's names (`map`, `flatMap`, `catch`, `retry`, `debounce`, `share`, …), plus `AfluentTesting` | Pipelines over async work where Combine would once have been used; a Combine replacement in new code. Products `"afluent/Afluent"` and, for test targets, `"afluent/AfluentTesting"`. |
| [DebugDrawer](https://github.com/Tyler-Keith-Thompson/DebugDrawer) | A plugin-based debug drawer for SwiftUI apps on iOS and macOS: a slide-in panel attached at the root view (`.debugDrawer()`), opened by `DebugDrawer.shared.toggle()`, with a library per plugin (console, performance, network, UserDefaults, app info, …) and local plugins tied to a view's lifetime (`.debugLocalPlugin(_:)`). It compiles to no-ops in release builds | Any debug-only tool an app needs (a switch, a fake response, a state dump): write a DebugDrawer plugin, installed from the composition root, instead of a one-off debug screen or gesture. Products are per plugin (`"debugdrawer/DebugDrawerConsolePlugin"`, …); the core is `"debugdrawer/DebugDrawer"`. |

Their conventions carry over: value types, typed errors, `checked:` spellings that throw where
the plain spelling traps, tests with Swift Testing.

## Workflow

### Adding a feature

A feature is done when it has all of these. Copy what its sibling features in the module already
have.

1. **Code and docs.** The implementation, with doc comments per "Docs" below. A new module gets a
   row in `scripts/modules.py`, then `just modules`, a line in the README's plugin list (a
   plugin) and a row in the core catalog's Modules article. A plugin's guide is an article in
   its module's DocC catalog (`Sources/<Module>/<Module>.docc`), linked from the README.
2. **Tests** in `Tests/<Module>Tests`:
   - hand-worked cases;
   - edge cases: empty input, one element, the boundaries of every range;
   - `checked:` spellings and their errors;
   - exit tests for every trap;
   - a property test against a naive reference (`swift-property-based`).
3. **A README example**, if the feature changes how the package is introduced, copied verbatim
   into `Tests/DebugDrawerTests`.
4. **A benchmark** in `Benchmarks/Benchmarks/<Module>Benchmarks` (a row in `BENCHMARKS`, then
   `just modules`) where speed matters, starting with a `BASELINE` entry: the same work with the
   plugin not installed, which installing must keep pace with. Measure in release, and add a
   ratio test in `Tests/<Module>Tests/Performance/` where siblings have one.
   Use small inputs in debug builds, because the timing only runs in release.
   Judge a speed change by `just bench-check --target <Module>Benchmarks` against the committed
   `main` baseline, on a quiet machine, and after a deliberate change in cost re-record it
   (`just bench-baseline --target X`) and commit it with the change. The simulated (Callgrind)
   baselines don't apply here: they measure in a Linux VM, and these benchmarks build on Apple
   platforms only.

Watch for these:

- A closure inside `#expect` nested in another closure can run the wrong body, or crash the
  Linux compiler. Put the body in a nested `func`.
- Hoist literals to typed `let`s rather than writing them inline in `#expect`.
- Iterate dictionary keys sorted wherever order is visible.

### What to run

| Change | Run |
|---|---|
| Any library code | `bazel test` for every target in `bazel query 'rdeps(//Tests/..., //Sources/X)'`, then `just test-release` |
| `scripts/modules.py` | `just modules`, `just test` (which runs `//:package_swift_test`), `just spm` |
| A public API the example apps call, or `Example/` | `bazel build //Example/...`, then `just run` (and `just run iOS`) to look at it |
| Network, DiskIO or Console interception, the stall monitor (`DebugDrawerHangDetector`), the leak detector, network mocking's URL protocol, the network log's filter, or `Benchmarks/` | `just bench-check` (`--target X` for the one changed); after a deliberate change in cost, `just bench-baseline --target X` and commit the baseline with it |
| A view module, or anything a view draws with | `just test` (lint, view and snapshot tests); `just record-snapshots` if it should look different, then review the images; `just spm-test` |
| `Benchmarks/`, or an API the benchmarks call | `cd Benchmarks && env -u TOOLCHAINS xcrun --toolchain default swift build -c release -Xswiftc -DDEBUG` (the benchmarks compile only with `DEBUG` defined) |

### Pushing

Push finished work to `main` yourself; don't wait to be asked, and never end a task with
finished commits unpushed. Push once per batch: when the work the owner gave you is done (the
whole request, or Ready is empty when working the backlog), push everything it produced together.
CI (`.github/workflows/ci.yml`) runs only when started by hand (`gh workflow run ci.yml --ref
<branch>`), so nothing checks a push but you: verify the committed state in a clean worktree
first, `bazel test //...` in debug, then `--config=release`, then `just spm-test`. The workflow
runs `just test`, `just test-spm` and `just test-ios` on a macOS runner and uploads failing
snapshots' diffs; it reads BuildBuddy's key from the `BUILDBUDDY_API_KEY` secret.

## House rules

### Code (*default*)

- **Declarative and composable.** Describe what a value is, not the steps that build it. Prefer
  small types and functions that compose (modifiers returning a new value, result builders,
  protocol extensions) over flags, configuration objects and long imperative bodies. A caller
  should be able to read an expression top to bottom and know the result.
- **Don't reinvent the wheel.** If the Swift ecosystem already has it, use it. Before writing a
  data structure, algorithm, parser, concurrency primitive or test tool, look in this order:
  1. The owner's libraries (Building blocks above).
  2. Apple: the standard library and Foundation, then Apple's open-source packages
     (swift-collections, swift-algorithms, swift-async-algorithms, swift-numerics, swift-atomics,
     swift-system, swift-argument-parser, swift-log, swift-crypto, swift-nio), then
     the platform frameworks where every target, Linux included, has them.
  3. Well-maintained community packages (Mockable and swift-property-based are already the
     picks for mocks and property tests).

  Write it yourself only when nothing fits: the package can't support the platforms, can't meet
  a measured performance need, or would pull in far more than the job needs. Say which package
  was rejected and why in the commit message.
- Public types are value types. Mutation returns a new value or is a clearly named `mutating`
  method; no shared mutable state reached through globals.
- Use the standard library's `Atomic`/`Mutex` or swift-atomics for shared state. No hand-rolled
  atomics.
- Names come from established libraries or the literature, familiar programmer terms first.
  Never invent names. No synonym typealiases; one name per concept. Spell names out.
- Delete unused API rather than keeping it.
- Small files, one main type each. Vocabulary a body needs goes in a `fileprivate` extension on
  the type it describes (`extension User { fileprivate func matches(_ term: String) -> Bool }`),
  so the body reads as a sentence.
- No hooks or SPI added only for tests.
- Underscored Swift features (`@_spi`, `_modify`, `@_effects`, `@_exported`) are fine where they
  help. Apple private API is not: undocumented framework symbols, private selectors, private
  frameworks, anything App Review rejects.

### Seams and composition (*default*)

How code that reaches past the process is split: networks, disks, clocks, other services. A pure
library with none of that can skip this section.

- **Layers with one job each.** A transport (HTTP, a file) knows nothing of the domain. A service
  built on it speaks one API. Persistence and features build on services. A module depends only
  on layers below it. Where two modules' models meet, an adapter in the module that imports both
  translates between them, rather than one importing the other. A few lines duplicated across
  modules cost less than coupling them; say so in a comment where it happens.
- **A protocol at every seam.** Anything a test must replace is a protocol marked `@Mockable`.
  Its production conformer is internal and takes the protocol's name with a leading underscore
  (`_SearchService`), so autocomplete offers the protocol. Beside it, a `Factory` on `Container`
  (DependencyInjection) returns it as the protocol, scoped on purpose: `.cached` for one instance
  that holds state, `.shared` for one instance while anyone holds it, unique otherwise. Callers
  resolve it with `@Injected`, `@LazyInjected` or `@ConstructorInjected`, never by naming the
  conformer.
- **The executable is the composition root.** Modules ship working defaults (an in-memory store);
  the executable registers what production swaps in (the store on disk) at startup.
- **Async work is a pipeline of values.** With Afluent, a call returns a lazy unit of work
  (`DeferredTask`, `AsynchronousUnitOfWork`) built from operators: `flatMap` to the next step,
  `tryMap` to validate, `decode`, `handleEvents` for side effects (caching, logging), `tryCatch`
  for a fallback, `shareFromCache` so simultaneous identical requests make one call. Nothing runs
  until `execute()`, so callers compose, retry and cancel it freely.
- **Time is a dependency.** Code that waits, debounces or times out takes a clock registered on
  `Container` (`AnyClock<Duration>`), never an inline `Task.sleep` or `ContinuousClock()`. Tests
  register a `TestClock` (swift-clocks) and advance it.
- **State is an enum of what can be true.** A screen, a response or a load is an enum with a case
  per state (`prompt`, `loading`, `results([User])`, `noResults(String)`, `failed`), mapped once
  from the outcome, not optionals and flags that can disagree.
- **Isolation states its reason.** Mutable state reached from async callers lives in an actor, or
  behind `Mutex` where the hops would cost too much; a comment says which and when to switch.
- **Literals checked at compile time.** A literal URL is `#URL("…")` (the URL macro), not
  `URL(string:)!`. A force unwrap or trap that remains has a comment proving it can't fire and
  why a crash beats a thrown error no caller could handle.
- **Logging.** A type that logs has one `private static let logger`: swift-log's
  `Logger(label: "<module>.<Type>")`, or `os.Logger(subsystem:category:)` in Apple-only code, where
  every interpolation of user data stays private. Levels mean something: `debug` for a path taken,
  `info` for a notable event, `notice` for a degraded result (cached data served), `error` for a
  failure. Cancellation is not a failure; don't log it as one. Logs are for developers; tests
  don't pin them.

### Tests (*default*)

- Swift Testing (`import Testing`, `@Suite`, `@Test`, `#expect`, `#require`). Never XCTest.
- Each test is self-contained and portable: no assertion or setup helpers, not DRY; a test
  copied to another file still works. Shared fixture data in `DebugDrawerTestSupport` is tolerated;
  shared assertions are not, except the interception contract's checks
  (`DebugDrawerInterceptionContract`), which every interception plugin must pass alike.
- Test names state the rule they pin ("The checked spelling throws EmptyName for an empty name").
- **Sociable.** A test runs the real code under test and its real collaborators wherever they are
  fast and deterministic, and mocks only the seams that reach out (network, disk, clock) or that
  it must steer. Inside `withTestContainer { }`, `Container.x.useProduction()` resolves the real
  subject; its seams get mocks.
- **Shape.** Arrange; then act on `sut`; then assert, with a blank line between. Name the values
  `expected…` and `actual`. Where the call itself is the rule, `verify(mock)` pins it:
  `.called(.once)`, or `.called(.never)` for one that must not happen.
- **Deterministic concurrency.** Never sleep to let something happen. Order concurrent work with
  gates the test opens (a stub that awaits a `SingleValueSubject` the test sends), advance a
  `TestClock`, and run main-actor tests under `withMainSerialExecutor` (swift-concurrency-extras).
  A suite that awaits carries `.timeLimit(.minutes(1))`, so a hang fails rather than stalls.
- **Unhappy paths.** Every failure a seam can produce (a timeout, no network, a malformed
  response, a missing resource) has a test of what the caller sees.
- Tests may call underscored and `package` API.
- Test doubles come from [Mockable](https://github.com/Kolos65/Mockable): mark the protocol at the
  seam `@Mockable` and use the generated `Mock<Protocol>` with `given`, `when` and `verify`
  inside the test, rather than hand-writing doubles. With DependencyInjection, register the mock
  inside the test's `withTestContainer { }`. Mocks exist only in debug builds, so a
  `PerformanceTests` target never uses one.
- Property tests use swift-property-based (`import PropertyBased`, `propertyCheck`).
- Randomized tests are seeded so a failure reproduces from its seed alone: a SwiftPRNG generator
  (`Xoshiro256StarStar(seed:)`), drawn through its platform-stable `uniform(in:)`, `integer(in:)`
  and `bernoulli(_:)` rather than the standard library's `random(in:using:)`, whose answers may
  change between Swift releases.

### Docs (*default*)

- Describe the current API. No history ("previously", "renamed"), design debates, comparisons
  with other libraries, or benchmark numbers in doc comments or READMEs. Complexity bounds are
  fine.
- Doc comments: a one-line summary, then parameters, return value, complexity, and what traps or
  throws.
- `//` comments say why, where the code makes a choice a reader would question: the data
  structure, an actor over a `Mutex`, deliberate duplication, a force unwrap, the package rejected
  and when it would become the right one. Doc comments describe the API; these record decisions. A
  comment that restates the code is deleted.
- The README's examples are tests (`Tests/DebugDrawerTests`).
- The README is the front page: what the project is, how to install or run it, one short example,
  and links. Everything else (guides, every option, reference) goes in the DocC catalogs, which
  the README links to. When a section grows past a screen, move it out rather than trim the
  README's other sections to make room.
- Run prose docs through the `humanizer` skill (`/humanizer`) before committing them: READMEs, DocC
  articles, doc comments and this file. It removes the tells of generated text (inflated claims,
  stock phrases, forced lists of three) without changing what the text says. Docs only: not code,
  `//` comments, commit messages or backlog items.

### Git (*default*)

- Commit message style: `[main] - <summary>`, no trailers (no co-author or session lines).
- One commit per finished feature or fix, after its suites pass.
- Never file bugs with third-party projects; record them locally.

## API conventions (*default*)

### Errors

- **Plain spellings trap** on a precondition failure, like an `Array` subscript. They are the
  fast path.
- **`checked:` spellings throw** a typed, payload-free error (`Greeting(checkedName:)` throws
  `EmptyName`). There are no nil-returning variants; `try?` gives `nil`.
- **Invariant-breaking mutations throw on the plain spelling** and change nothing, with one typed
  error per invariant whose cases make a single `catch` exhaustive.
- **Queries whose failure is the answer return a witness** (`findCycle() -> Cycle?`), not an
  error.

### Shapes

- Results are dedicated types, not tuples.
- Lazy views end in `View`; the materialized form drops the suffix.
- Materializing operations are static factories on a target the caller picks.

### Performance patterns

- Public types are copy-on-write structs, `@frozen`, with `@usableFromInline` internals.
  Hot generic code is `@inlinable`; parameters are `some` generics, never `any`.
- Copy-on-write: the uniqueness check is inlined and the reallocation slow path is
  `@inline(never)`. Bulk mutations check uniqueness once, outside the loop.
- Traps measured in past projects: nested functions capturing mutable locals (boxed, retained
  per step); generic iterators stored in arrays (use integer cursors); reading a struct out of a
  class property (copies and retains); lazy maps capturing `self`.
- Write overflow guards as comparisons (`x <= Int.max / 4`), not a discarded
  `multipliedReportingOverflow` result.
