PROJECT_ROOT := justfile_directory()
BAZEL := "bazel"

# Registers a Mac example with Launch Services after `just run` re-extracts and signs it. locationd
# keeps a Location grant across a rebuild only for an app Launch Services knows; for one it doesn't
# (a fresh copy in /tmp), every new build asks again, even with the same signing identity.
LSREGISTER := "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f"

# Optimized builds use a separate output base: switching --compilation_mode changes the
# configuration, and sharing a base with debug builds would discard the analysis cache on every
# switch (which .bazelrc refuses). Each checkout gets its own, so two never wait on one server's
# lock or overwrite each other's outputs. It sits in Bazel's output user root under a 32-digit hex
# name like the debug base's, where tools/sweep-output-bases deletes it once its checkout is gone.
BAZEL_RELEASE_OUTPUT_BASE := cache_directory() / "bazel" / ("_bazel_" + env("USER", "root")) / replace_regex(sha256(PROJECT_ROOT + ":release"), '^(.{32}).*$', '$1')
BAZEL_RELEASE := "bazel --output_base=" + BAZEL_RELEASE_OUTPUT_BASE

# Device builds (just run device) change the CPU the same way, so they get a base of their own too.
BAZEL_DEVICE_OUTPUT_BASE := cache_directory() / "bazel" / ("_bazel_" + env("USER", "root")) / replace_regex(sha256(PROJECT_ROOT + ":device"), '^(.{32}).*$', '$1')
BAZEL_DEVICE := "bazel --output_base=" + BAZEL_DEVICE_OUTPUT_BASE

# SwiftPM runs through Xcode's default toolchain. A development snapshot selected through
# TOOLCHAINS (or first on PATH via swiftly) can fail to read the SDK's Testing module.
SWIFT := "env -u TOOLCHAINS xcrun --toolchain default swift"

# Every xcodebuild recipe compiles with Xcode's compilation caching, in one store under
# ~/Library/Caches that every checkout shares (scripts/xcode_cache.py), so a fresh worktree replays
# what another already compiled instead of building it all again. SwiftPM's own `swift build` has
# no such setting, so spm-test-mac still compiles everything in a new worktree.

[doc('Build everything (default)')]
all: build

[doc('Lint, then build every target')]
build: lint
    {{BAZEL}} build //...

[doc('Lint, then run every test')]
test: lint
    {{BAZEL}} test //...

# SwiftPM compiles #filePath as an absolute path, so SnapshotTesting writes each reference beside
# its test; under Bazel it would land in the test's runfiles. Recording reports every snapshot it
# wrote as an issue, so the tests fail; run `just test` afterwards to check against them. Then the
# generator runs, since a target's first __Snapshots__ needs excluding from Package.swift.
[doc('Re-record every snapshot reference into the workspace, after a change to how a view looks')]
record-snapshots:
    -SNAPSHOT_TESTING_RECORD=all just spm-test-mac
    -just test-ios TEST_RUNNER_SNAPSHOT_TESTING_RECORD=all
    python3 {{PROJECT_ROOT}}/scripts/modules.py

# macOS doesn't scale text with Dynamic Type, so the large-text snapshots (under #if os(iOS)) run
# on an iOS simulator through xcodebuild. xcodebuild hands the test process only the variables
# prefixed TEST_RUNNER_, which is how record-snapshots asks it to record. The renderer draws at a
# fixed width and scale, so any simulator gives the same references. Like every SwiftPM run, it
# builds the performance targets in debug and runs none of them (PERFORMANCE_TESTS in
# scripts/modules.py); Bazel runs them, optimized under `just test-release`.
# Each checkout runs on a simulator of its own (scripts/ios_simulator.py): an iPad Pro 13-inch (M5),
# the snapshots' model, on the newest iOS runtime, made on first use and reused, so runs from two
# worktrees don't launch their test hosts over each other. An IOS_DESTINATION given (CI's) wins.
IOS_DESTINATION := env("IOS_DESTINATION", "")

# Tests to leave out of every SwiftPM test run: spm-test-mac's swift test, spm-platform-test's,
# spm-catalyst-test's and test-ios's xcodebuild. Entries go comma- or space-separated in
# xcodebuild's -skip-testing form, Target, Target/Suite or Target/Suite/test() (a Swift Testing
# function keeps its parentheses and labels, or xcodebuild skips nothing), and
# scripts/test_skips.py writes them as each runner takes them: `--skip` regexes for swift test,
# `-skip-testing:` for xcodebuild. Exported, so the stages spm-test runs as recipes of their own see
# it whether it was given before the recipe (`just SKIP_TESTS=... spm-test`) or in the environment.
export SKIP_TESTS := env("SKIP_TESTS", "")

[doc('Run the SwiftPM tests on an iOS simulator (the Dynamic Type snapshots), this checkout’s own unless IOS_DESTINATION names one; SKIP_TESTS="Target/Suite/test(),…" leaves tests out, as in spm-test')]
test-ios *env="":
    #!/usr/bin/env bash
    set -euo pipefail
    destination='{{IOS_DESTINATION}}'
    if [ -z "$destination" ]; then
        destination="platform=iOS Simulator,id=$(python3 {{PROJECT_ROOT}}/scripts/ios_simulator.py udid)"
    fi
    skips=$(python3 {{PROJECT_ROOT}}/scripts/modules.py performance-targets | sed 's/^/-skip-testing:/')
    skipped=$(python3 {{PROJECT_ROOT}}/scripts/test_skips.py xcodebuild)
    derived={{PROJECT_ROOT}}/.build/xcode-ios
    settings=$(python3 {{PROJECT_ROOT}}/scripts/xcode_cache.py "$derived")
    cache=(); while IFS= read -r setting; do cache+=("$setting"); done <<< "$settings"
    env {{env}} xcodebuild test -quiet -scheme DebugDrawer-Package -destination "$destination" \
        -derivedDataPath "$derived" "${cache[@]}" $skips $skipped

[doc('Delete the simulator just test-ios made for this checkout (run it before removing a worktree)')]
ios-simulator-delete:
    python3 {{PROJECT_ROOT}}/scripts/ios_simulator.py delete

[doc('Delete the simulators just test-ios made for checkouts that no longer exist, such as removed worktrees')]
ios-simulator-prune:
    python3 {{PROJECT_ROOT}}/scripts/ios_simulator.py prune

[doc('SwiftLint and a11y-check over every first-party target (tools/lint.bzl)')]
lint:
    {{BAZEL}} build //... --config=lint

[doc('Run one test target, e.g. just test-one //Tests/GreetingsTests')]
test-one target:
    {{BAZEL}} test {{target}}

[doc('Run tests matching a filter, e.g. just filter Greeting')]
filter pattern:
    {{BAZEL}} test //... --test_filter={{pattern}}

[doc('Run the speed-reliant tests (the PerformanceTests targets) optimized (-O); the rest run in debug only')]
test-release:
    {{BAZEL_RELEASE}} test --config=release //...

# The interception the benchmarks measure is DEBUG-only, so they build optimized (the plugin's
# release configuration) with DEBUG defined for every module; each benchmark source refuses to
# compile without it. --disable-sandbox: the Network benchmarks listen on the loopback interface
# and the DiskIO ones write to the temporary directory, which the plugin sandbox forbids.
BENCH := "cd " + PROJECT_ROOT + "/Benchmarks && " + SWIFT + " package --disable-sandbox -Xswiftc -DDEBUG benchmark"

[doc('Run the interception benchmarks (Benchmarks/), installed against not installed, e.g. just bench, or just bench --target DebugDrawerNetworkPluginBenchmarks')]
bench *args="":
    {{BENCH}} {{args}}

[doc('Record the benchmarks as the committed main baseline, which just bench-check gates against')]
bench-baseline *args="":
    {{BENCH}} baseline update main --no-progress {{args}}

[doc('Run the benchmarks and show how they differ from the main baseline')]
bench-compare *args="":
    {{BENCH}} baseline compare main --no-progress {{args}}

# `swift package` exits 1 whenever ordo-one's `baseline check` fails, which it does on a regression
# past a benchmark's thresholds (benchmarkThresholdRegression) and also when it finds only
# improvements (benchmarkThresholdImprovement). An improvement passes the gate; re-record with
# bench-baseline to keep it.
[doc('The regression gate: run the benchmarks and fail when one regresses past its threshold against the main baseline (Benchmarks/README.md); for CI')]
bench-check *args="":
    #!/usr/bin/env bash
    set -uo pipefail
    log=$(mktemp)
    trap 'rm -f "$log"' EXIT
    {{BENCH}} baseline check main --no-progress {{args}} 2>&1 | tee "$log"
    status=${PIPESTATUS[0]}
    if [ "$status" -ne 0 ] && grep -q "error: benchmarkThresholdImprovement" "$log"; then
        echo "Only improvements against the main baseline; re-record it with just bench-baseline to keep them."
        exit 0
    fi
    exit "$status"

[doc('Re-resolve SwiftPM dependencies for Bazel after editing PACKAGES in scripts/modules.py')]
resolve:
    cd {{PROJECT_ROOT}}/swift && {{SWIFT}} package resolve

[doc('Build via SwiftPM too, to verify the published package (the Mac, then the visionOS, tvOS, watchOS and Mac Catalyst modules, and the iOS example for Mac Catalyst)')]
spm:
    {{SWIFT}} build
    just spm-visionos
    just spm-tvos
    just spm-watchos
    just spm-catalyst
    just spm-catalyst-example

# `swift build` builds for the host only, so xcodebuild builds the modules ported to another
# platform (EXTRA_PLATFORMS in scripts/modules.py) for its simulator, from the same Package.swift.
[doc('Build the modules ported to a platform through SwiftPM for its simulator, e.g. just spm-platform tvOS')]
spm-platform platform:
    #!/usr/bin/env bash
    set -euo pipefail
    derived={{PROJECT_ROOT}}/.build/xcode-{{lowercase(platform)}}
    settings=$(python3 {{PROJECT_ROOT}}/scripts/xcode_cache.py "$derived")
    cache=(); while IFS= read -r setting; do cache+=("$setting"); done <<< "$settings"
    for module in $(python3 {{PROJECT_ROOT}}/scripts/modules.py platform-modules {{platform}}); do
        xcodebuild build -quiet -scheme "$module" -destination 'generic/platform={{platform}} Simulator' \
            -derivedDataPath "$derived" "${cache[@]}" SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
    done

[doc('Build the visionOS modules through SwiftPM for the visionOS simulator')]
spm-visionos: (spm-platform "visionOS")

# A platform's tested targets (TESTED_PLATFORMS in scripts/modules.py) each run through a scheme
# that modules.py writes into .swiftpm/ holding just that test target, so xcodebuild builds only
# what it tests, never the modules not ported there; DebugDrawer-Package would build them all,
# with or without -only-testing.
[doc('Run the test targets ported to a platform through SwiftPM in its simulator, e.g. just spm-platform-test visionOS "platform=visionOS Simulator,name=Apple Vision Pro"')]
spm-platform-test platform destination:
    #!/usr/bin/env bash
    set -euo pipefail
    derived={{PROJECT_ROOT}}/.build/xcode-{{lowercase(platform)}}
    settings=$(python3 {{PROJECT_ROOT}}/scripts/xcode_cache.py "$derived" --tests)
    cache=(); while IFS= read -r setting; do cache+=("$setting"); done <<< "$settings"
    for scheme in $(python3 {{PROJECT_ROOT}}/scripts/modules.py platform-test-schemes {{platform}}); do
        skipped=$(python3 {{PROJECT_ROOT}}/scripts/test_skips.py xcodebuild "$scheme")
        xcodebuild test -quiet -scheme "$scheme" -destination '{{destination}}' \
            -derivedDataPath "$derived" "${cache[@]}" $skipped
    done

# The simulator `just spm-visionos-test` runs the visionOS tests in.
VISIONOS_DESTINATION := env("VISIONOS_DESTINATION", "platform=visionOS Simulator,name=" + VISIONOS_DEVICE)

[doc("Run the visionOS test targets (core's) through SwiftPM in the visionOS simulator")]
spm-visionos-test: (spm-platform-test "visionOS" VISIONOS_DESTINATION)

[doc('Build the tvOS modules through SwiftPM for the tvOS simulator')]
spm-tvos: (spm-platform "tvOS")

# The simulator `just spm-tvos-test` runs the tvOS tests in.
TVOS_DESTINATION := env("TVOS_DESTINATION", "platform=tvOS Simulator,name=" + TVOS_DEVICE)

[doc("Run the tvOS test targets (core's) through SwiftPM in the tvOS simulator")]
spm-tvos-test: (spm-platform-test "tvOS" TVOS_DESTINATION)

[doc('Build the watchOS modules through SwiftPM for the watchOS simulator')]
spm-watchos: (spm-platform "watchOS")

# The simulator `just spm-watchos-test` runs the watchOS tests in.
WATCHOS_DESTINATION := env("WATCHOS_DESTINATION", "platform=watchOS Simulator,name=" + WATCHOS_DEVICE)

[doc("Run the watchOS test targets (core's) through SwiftPM in the watchOS simulator")]
spm-watchos-test: (spm-platform-test "watchOS" WATCHOS_DESTINATION)

# Package.swift's `.iOS` covers Mac Catalyst, so it is a destination rather than a platform.
[doc('Build the Mac Catalyst modules (CATALYST_MODULES in scripts/modules.py) through SwiftPM')]
spm-catalyst:
    #!/usr/bin/env bash
    set -euo pipefail
    derived={{PROJECT_ROOT}}/.build/xcode-catalyst
    settings=$(python3 {{PROJECT_ROOT}}/scripts/xcode_cache.py "$derived")
    cache=(); while IFS= read -r setting; do cache+=("$setting"); done <<< "$settings"
    for module in $(python3 {{PROJECT_ROOT}}/scripts/modules.py catalyst-modules); do
        xcodebuild build -quiet -scheme "$module" -destination 'generic/platform=macOS,variant=Mac Catalyst' \
            -derivedDataPath "$derived" "${cache[@]}" SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
    done

# The package holds every Example/iOS file and every example library and product their imports
# name, derived from the sources (scripts/catalyst_example.py); a file left out
# (CATALYST_EXAMPLE_EXCLUDE=Example/iOS/<file>) fails the build.
[doc('Build the iOS example as a Mac Catalyst app through SwiftPM, without launching it')]
spm-catalyst-example:
    python3 {{PROJECT_ROOT}}/scripts/catalyst_example.py build

# Every test target, built for Mac Catalyst and run in a Mac window's process, so the
# targetEnvironment(macCatalyst) branches run as well as build. Snapshot tests sit out
# (APPLE_ONLY_PACKAGE_EXCLUDED_PLATFORMS in scripts/modules.py), and so do tests that make a UIKit
# window: xctest runs them without an NSApplication. The test process runs on the Mac, so it gets
# a temporary home folder as spm-test-mac's does; xcodebuild hands it the variables prefixed
# TEST_RUNNER_. The performance targets are built but not run, as in every SwiftPM run.
[doc('Run every test target but the performance ones through SwiftPM for Mac Catalyst')]
spm-catalyst-test:
    #!/usr/bin/env bash
    set -euo pipefail
    skips=$(python3 {{PROJECT_ROOT}}/scripts/modules.py performance-targets | sed 's/^/-skip-testing:/')
    skipped=$(python3 {{PROJECT_ROOT}}/scripts/test_skips.py xcodebuild)
    derived={{PROJECT_ROOT}}/.build/xcode-catalyst-test
    settings=$(python3 {{PROJECT_ROOT}}/scripts/xcode_cache.py "$derived" --tests)
    cache=(); while IFS= read -r setting; do cache+=("$setting"); done <<< "$settings"
    home=$(mktemp -d)
    trap 'rm -rf "$home"' EXIT
    xcodebuild test -quiet -scheme DebugDrawer-Package -destination 'platform=macOS,variant=Mac Catalyst' \
        -derivedDataPath "$derived" "${cache[@]}" TEST_RUNNER_CFFIXED_USER_HOME="$home" $skips $skipped

# Plugins keep their files in Application Support and Caches under the home folder, which on macOS
# Foundation reads from CFFIXED_USER_HOME (never HOME), so the test process and every exit test's
# child get a temporary one, removed afterwards. SwiftPM keeps its own caches and configuration
# under the home folder too, so the tests are built with the real one and only the run moves.
# The arguments pass through as given (positional), so a quoted filter such as "A|B" stays one.
# The performance targets (PERFORMANCE_TESTS in scripts/modules.py) are built but skipped: their
# wall-clock budgets hold only in the optimized build Bazel runs each alone (`just test-release`),
# not in a debug build beside every other test. Further --skip arguments add to that one, and so do
# the tests SKIP_TESTS names; a --skip reaches only this stage, SKIP_TESTS every one.
[doc('Run the SwiftPM tests on the Mac but the performance ones, in a temporary home folder (arguments go to swift test)')]
[positional-arguments]
spm-test-mac *args:
    #!/usr/bin/env bash
    set -euo pipefail
    skipped=$(python3 {{PROJECT_ROOT}}/scripts/test_skips.py swift-test)
    {{SWIFT}} build --build-tests
    home=$(mktemp -d)
    trap 'rm -rf "$home"' EXIT
    skip=$(python3 {{PROJECT_ROOT}}/scripts/modules.py swift-test-performance-skip)
    CFFIXED_USER_HOME="$home" {{SWIFT}} test --skip-build --skip "$skip" $skipped "$@"

[doc('Run the tests via SwiftPM but the performance ones: on the Mac (arguments go to swift test), then the visionOS, tvOS and watchOS ones in their simulators and the rest for Mac Catalyst. To skip a test in every stage, name it in SKIP_TESTS, e.g. SKIP_TESTS="DebugDrawerTests/CaptureBufferTests/countBound(),DebugDrawerNetworkPluginTests/NetworkWebSocketExitTests" just spm-test; a --skip reaches swift test only')]
[positional-arguments]
spm-test *args:
    just spm-test-mac "$@"
    just spm-visionos-test
    just spm-tvos-test
    just spm-watchos-test
    just spm-catalyst-test

[doc('Verify both build systems agree — run before pushing')]
verify: test spm-test

# The board's charter names the SwiftPM recipes build-spm and test-spm.
alias build-spm := spm
alias test-spm := spm-test

[doc('Regenerate Package.swift and every BUILD.bazel from scripts/modules.py')]
modules:
    python3 {{PROJECT_ROOT}}/scripts/modules.py

[doc('Precompile every Sources/*/Shaders/*.metal into Swift sources (needs the Metal toolchain Xcode downloads)')]
metallibs:
    python3 {{PROJECT_ROOT}}/tools/metallibs.py

[doc('Refresh the checked-in copies of generated sources (GENERATED_SOURCES in scripts/modules.py) that SwiftPM compiles')]
sources:
    #!/usr/bin/env bash
    set -euo pipefail
    cd {{PROJECT_ROOT}}
    targets=$({{BAZEL}} query 'attr(generator_function, generated_swift_source, kind(genrule, //Sources/... + //Tests/...))')
    [ -n "$targets" ] || { echo "No generated sources (GENERATED_SOURCES in scripts/modules.py)."; exit 0; }
    {{BAZEL}} build $targets
    for target in $targets; do
        package="${target#//}"; package="${package%%:*}"
        for output in $({{BAZEL}} cquery "$target" --output=files 2>/dev/null); do
            copy="$package/Generated/${output#*/bin/$package/}"
            mkdir -p "$(dirname "$copy")"
            install -m 644 "$output" "$copy"
        done
    done

[doc('Build the combined DocC site for every library module into .build/docs')]
docs:
    {{BAZEL}} build //:docs
    rm -rf {{PROJECT_ROOT}}/.build/docs && mkdir -p {{PROJECT_ROOT}}/.build
    cp -RL {{PROJECT_ROOT}}/bazel-bin/docs {{PROJECT_ROOT}}/.build/docs && chmod -R u+w {{PROJECT_ROOT}}/.build/docs

[doc('Generate an Xcode project from the Bazel graph and open it')]
generate *args="":
    @bash scripts/generate-xcodeproj.sh {{args}}

[doc('Build optimized: the library and the speed-reliant tests, not the debug-only test targets')]
release:
    {{BAZEL_RELEASE}} build --config=release //...

# Every public API keeps a release stand-in, so callers compile unchanged without DEBUG (the
# charter's rules). Two checks, since neither covers the other: the example apps call the drawer
# and every shipped plugin's install with no `#if DEBUG`, so their optimized build fails when a
# call they make has no stand-in; and scripts/release_api.py compares every library module's
# public symbols and conformances, built through SwiftPM in debug and in release, so a symbol no
# example calls is checked too.
[doc('Check that release builds keep the public API: build the example apps optimized, then compare each module’s public symbols in debug and release')]
release-check:
    {{BAZEL_RELEASE}} build --config=release //Example/...
    python3 {{PROJECT_ROOT}}/scripts/release_api.py check --swift "{{SWIFT}}"

# The simulators `just run sidecar`, `just run visionOS`, `just run tvOS` and `just run watchOS`
# boot, by name.
IOS_DEVICE := env("IOS_DEVICE", "iPhone 18 Pro")
VISIONOS_DEVICE := env("VISIONOS_DEVICE", "Apple Vision Pro")
TVOS_DEVICE := env("TVOS_DEVICE", "Apple TV 4K (4th generation)")
WATCHOS_DEVICE := env("WATCHOS_DEVICE", "Apple Watch Series 12 (46mm)")

[doc('Build and launch an example app: just run, just run iOS, just run device (the iOS example on a paired iPhone), just run appkit, just run uikit, just run sidecar [iOS|macOS], just run catalyst, just run visionOS, just run tvOS or just run watchOS')]
run target="macOS" *args="":
    #!/usr/bin/env bash
    set -euo pipefail
    # Builds an example app for a simulator, installs it from a writable copy (the simulator can't
    # copy Bazel's read-only bundle) and launches it, with the arguments after the first four.
    # Extra arguments go to the app; -OpenDebugDrawer opens the drawer at launch.
    run_in_simulator() {
        local target="$1" device="$2" bundle_id="$3" run_dir="$4"
        shift 4
        rm -rf "$run_dir"
        mkdir -p "$run_dir"
        {{BAZEL}} build "//Example:$target"
        local output
        output=$({{BAZEL}} cquery "//Example:$target" --output=files 2>/dev/null | grep -E '\.(app|ipa|zip)$')
        # rules_apple hands visionOS a bundle, tvOS an .ipa, whose Payload holds the bundle, and
        # watchOS a .zip of the bundle.
        case "$output" in
            *.ipa) unzip -qo "$output" -d "$run_dir" && mv "$run_dir/Payload/"*.app "$run_dir/" ;;
            *.zip) unzip -qo "$output" -d "$run_dir" ;;
            *) cp -RL "$output" "$run_dir/" ;;
        esac
        chmod -R u+w "$run_dir"
        xcrun simctl boot "$device" 2>/dev/null || true
        xcrun simctl bootstatus "$device" -b
        xcrun simctl install "$device" "$run_dir/"*.app
        xcrun simctl launch "$device" "$bundle_id" "$@"
    }
    case "{{target}}" in
        macOS|macos)
            RUN_DIR="/tmp/debugdrawer-example"
            rm -rf "$RUN_DIR"
            mkdir -p "$RUN_DIR"
            {{BAZEL}} build //Example:ExampleApp_macOS
            APP_ZIP=$({{BAZEL}} cquery //Example:ExampleApp_macOS --output=files 2>/dev/null | grep '\.zip$')
            unzip -qo "$APP_ZIP" -d "$RUN_DIR"
            # Re-signed with the Keychain's Apple Development identity (or DEBUGDRAWER_SIGN_IDENTITY;
            # `-` for ad hoc) and kept at this path, so macOS keeps its privacy grants across rebuilds.
            python3 {{PROJECT_ROOT}}/scripts/sign_example.py "$RUN_DIR/DebugDrawerExample.app"
            {{LSREGISTER}} "$RUN_DIR/DebugDrawerExample.app"
            open "$RUN_DIR/DebugDrawerExample.app"
            ;;
        iOS|ios)
            {{BAZEL}} run //Example:ExampleApp_iOS
            ;;
        device|Device)
            # The iOS example on a paired iPhone or iPad (DEBUGDRAWER_DEVICE picks one by name or
            # UDID), signed with the profile Xcode's automatic signing made for it. The check
            # names the missing setup, a device or that profile, before anything builds.
            UDID=$(python3 {{PROJECT_ROOT}}/scripts/device_example.py check)
            RUN_DIR="/tmp/debugdrawer-example-device"
            rm -rf "$RUN_DIR"
            mkdir -p "$RUN_DIR"
            {{BAZEL_DEVICE}} build --config=device //Example:ExampleApp_iOS
            IPA=$({{BAZEL_DEVICE}} cquery --config=device //Example:ExampleApp_iOS --output=files 2>/dev/null | grep '\.ipa$')
            unzip -qo "$IPA" -d "$RUN_DIR"
            xcrun devicectl device install app --device "$UDID" "$RUN_DIR/Payload/DebugDrawerExample.app"
            xcrun devicectl device process launch --device "$UDID" com.debugdrawer.example.ios {{args}}
            ;;
        appkit|AppKit)
            # The AppKit-only Mac example: no SwiftUI root, the test bench in its Debug menu.
            RUN_DIR="/tmp/debugdrawer-example-appkit"
            rm -rf "$RUN_DIR"
            mkdir -p "$RUN_DIR"
            {{BAZEL}} build //Example:ExampleApp_macOSAppKit
            APP_ZIP=$({{BAZEL}} cquery //Example:ExampleApp_macOSAppKit --output=files 2>/dev/null | grep '\.zip$')
            unzip -qo "$APP_ZIP" -d "$RUN_DIR"
            open "$RUN_DIR/DebugDrawerAppKitExample.app" --args {{args}}
            ;;
        uikit|UIKit)
            # The UIKit-only iOS example: no SwiftUI root, the test bench behind its Test Bench button.
            {{BAZEL}} run //Example:ExampleApp_iOSUIKit
            ;;
        sidecar|Sidecar)
            # The example sidecar (Example/Sidecar, built from DebugDrawerSidecarKit) beside the
            # production host it drives (Example/Receiver): in the iOS simulator, or with `macOS`
            # on the Mac.
            case "{{args}}" in
                ""|iOS|ios)
                    # Two of the group's apps, each serving its own directory of the group's store
                    # (apps/<bundle ID>/), so the sidecar lists both: the production host and the
                    # iOS example's debug build.
                    run_in_simulator ExampleApp_Receiver_iOS "{{IOS_DEVICE}}" com.debugdrawer.example.receiver \
                        /tmp/debugdrawer-example-receiver-ios
                    run_in_simulator ExampleApp_iOS "{{IOS_DEVICE}}" com.debugdrawer.example.ios \
                        /tmp/debugdrawer-example-ios
                    run_in_simulator ExampleApp_Sidecar_iOS "{{IOS_DEVICE}}" com.debugdrawer.example.sidecar \
                        /tmp/debugdrawer-example-sidecar-ios
                    ;;
                macOS|macos)
                    RUN_DIR="/tmp/debugdrawer-example-sidecar"
                    rm -rf "$RUN_DIR"
                    mkdir -p "$RUN_DIR"
                    {{BAZEL}} build //Example:ExampleApp_Receiver_macOS //Example:ExampleApp_Sidecar_macOS
                    for target in ExampleApp_Receiver_macOS ExampleApp_Sidecar_macOS; do
                        unzip -qo "$({{BAZEL}} cquery "//Example:$target" --output=files 2>/dev/null | grep '\.zip$')" -d "$RUN_DIR"
                    done
                    # Signed as `just run macOS` signs, into the app group named after the signing
                    # team, which needs no provisioning profile on the Mac; signed ad hoc, the two
                    # share a folder in Caches instead (Example/SidecarStore).
                    for app in "$RUN_DIR"/*.app; do
                        python3 {{PROJECT_ROOT}}/scripts/sign_example.py --app-group com.debugdrawer.example "$app"
                        {{LSREGISTER}} "$app"
                    done
                    open "$RUN_DIR/DebugDrawerReceiverExample.app"
                    open "$RUN_DIR/DebugDrawerSidecarExample.app"
                    ;;
                *)
                    echo "Unknown platform: {{args}}. Use 'just run sidecar' (iOS) or 'just run sidecar macOS'"
                    exit 1
                    ;;
            esac
            ;;
        catalyst|Catalyst)
            # The iOS example as a Mac Catalyst app, built through SwiftPM (Bazel has no Catalyst).
            python3 {{PROJECT_ROOT}}/scripts/catalyst_example.py build
            python3 {{PROJECT_ROOT}}/scripts/catalyst_example.py launch {{args}}
            ;;
        visionOS|visionos)
            run_in_simulator ExampleApp_visionOS "{{VISIONOS_DEVICE}}" com.debugdrawer.example.visionos \
                /tmp/debugdrawer-example-visionos {{args}}
            ;;
        tvOS|tvos)
            run_in_simulator ExampleApp_tvOS "{{TVOS_DEVICE}}" com.debugdrawer.example.tvos \
                /tmp/debugdrawer-example-tvos {{args}}
            ;;
        watchOS|watchos)
            run_in_simulator ExampleApp_watchOS "{{WATCHOS_DEVICE}}" com.debugdrawer.example.watchos \
                /tmp/debugdrawer-example-watchos {{args}}
            ;;
        *)
            echo "Unknown target: {{target}}. Use 'macOS', 'iOS', 'appkit', 'uikit', 'sidecar', 'catalyst', 'visionOS', 'tvOS' or 'watchOS'"
            exit 1
            ;;
    esac

# Before anything slow, the release gates (scripts/release.py): CHANGELOG.md must have an entry for
# the new version, and the public API must not break the last tag's (SwiftPM's
# diagnose-api-breaking-changes) unless the bump is major or `allow-breaking` is given. The owner
# releases patch bumps, so a patch that knowingly carries a break says so on the command line,
# where it is visible and never left set in a shell; the breaks it allows are listed in the
# release notes. Then `release-check`: the example apps build optimized and every public symbol
# exists in release. `dry-run` runs only the gates, on the working tree, and prints the notes.
[doc('Release origin/main as a new version: check CHANGELOG.md and the public API, verify, tag it, push only the tag and create the GitHub release; runs from any worktree whose HEAD is origin/main, e.g. just deploy, just deploy patch allow-breaking, just deploy patch dry-run')]
deploy bump="patch" *options="":
    #!/usr/bin/env bash
    set -euo pipefail
    ALLOW_BREAKING=""
    DRY_RUN=no
    for option in {{options}}; do
        case "$option" in
            allow-breaking) ALLOW_BREAKING=--allow-breaking ;;
            dry-run) DRY_RUN=yes ;;
            *) echo "Unknown option: $option. Use allow-breaking or dry-run." >&2; exit 1 ;;
        esac
    done
    NEW_VERSION=$(python3 {{PROJECT_ROOT}}/scripts/release.py next-version {{bump}})
    NOTES="{{PROJECT_ROOT}}/.build/release-notes/${NEW_VERSION}.md"
    gate() {
        python3 {{PROJECT_ROOT}}/scripts/release.py gate {{bump}} --swift "{{SWIFT}}" --notes-file "$NOTES" $ALLOW_BREAKING
        just release-check
    }
    if [ "$DRY_RUN" = yes ]; then
        gate
        echo "Dry run: would verify, tag ${NEW_VERSION}, push the tag and create its GitHub release with these notes:"
        cat "$NOTES"
        exit 0
    fi
    if [ -n "$(git status --porcelain)" ]; then
        echo "Error: working tree is dirty. Commit or stash changes first."
        exit 1
    fi
    just _require-origin-main
    gate
    # Every drawer entry point is #if DEBUG, so the tests run in debug; release must still build,
    # which the gate's release-check has shown for the example apps and the public API.
    just verify
    just release
    just _push-version-tag "${NEW_VERSION}"
    gh release create "${NEW_VERSION}" --title "${NEW_VERSION}" --notes-file "$NOTES" --verify-tag
    echo "Released ${NEW_VERSION}: $(gh repo view --json url -q .url)/releases/tag/${NEW_VERSION}"

# Refuses unless HEAD is origin/main's tip, so a release is always of what main holds on the
# remote, never of a local branch, whatever branch this worktree has checked out.
_require-origin-main:
    #!/usr/bin/env bash
    set -euo pipefail
    git fetch origin
    if [ "$(git rev-parse HEAD)" != "$(git rev-parse origin/main)" ]; then
        echo "Error: HEAD ($(git rev-parse --short HEAD)) is not origin/main ($(git rev-parse --short origin/main)). Release from a checkout of origin/main." >&2
        exit 1
    fi

# Tags HEAD with the version deploy gated (scripts/release.py next-version) and pushes only that
# tag, never a branch, so a local main that is behind (or another worktree's branch) is neither
# pushed nor needed.
_push-version-tag version:
    #!/usr/bin/env bash
    set -euo pipefail
    just _require-origin-main
    echo "Current: $(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || echo none)"
    echo "    New: {{version}}"
    git tag -a "{{version}}" -m "Release {{version}}"
    git push origin "{{version}}"

[doc('Store the BuildBuddy API key in the login Keychain (asks for it), once per Mac: every project from the template then builds with the remote cache (tools/bazel)')]
buildbuddy-key:
    #!/usr/bin/env bash
    set -euo pipefail
    read -r -s -p "BuildBuddy API key (hidden): " key
    echo
    if [ -z "$key" ]; then
        echo "No key entered; nothing stored" >&2
        exit 1
    fi
    # Through security's own command reader, so the key never appears in a process's arguments.
    printf 'add-generic-password -U -s buildbuddy -a api-key -l "BuildBuddy API key" -w %s\n' "$key" | security -i >/dev/null
    echo "Stored. Builds use BuildBuddy from the next Bazel command."

# The checkout of ProjectTemplate this project came from; .template.json records the commit.
PROJECT_TEMPLATE := env("PROJECT_TEMPLATE", home_directory() / "workspace" / "ProjectTemplate")

[doc('Merge the project template’s changes since .template.json’s commit into this checkout (needs a clean worktree), e.g. just template-update, or just template-update --to <commit>')]
template-update *args="":
    python3 {{PROJECT_TEMPLATE}}/template.py update {{PROJECT_ROOT}} {{args}}

[doc('Remove all build artifacts')]
clean:
    {{BAZEL}} clean
    {{BAZEL_RELEASE}} clean || true
    rm -rf {{PROJECT_ROOT}}/.build {{PROJECT_ROOT}}/Benchmarks/.build

[doc('Print the dependency graph of a target')]
deps target="//Sources/DebugDrawer":
    {{BAZEL}} query 'deps({{target}})' --output=label_kind

[doc('List every buildable target')]
targets:
    {{BAZEL}} query '//...' --output=label_kind
