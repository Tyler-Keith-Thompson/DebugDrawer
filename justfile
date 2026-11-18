PROJECT_ROOT := justfile_directory()
BAZEL := "bazel"

# Optimized builds use a separate output base: switching --compilation_mode changes the
# configuration, and sharing a base with debug builds would discard the analysis cache on every
# switch (which .bazelrc refuses).
BAZEL_RELEASE := "bazel --output_base=" + home_directory() + "/Library/Caches/bazel-debugdrawer-release"

# SwiftPM runs through Xcode's default toolchain. A development snapshot selected through
# TOOLCHAINS (or first on PATH via swiftly) can fail to read the SDK's Testing module.
SWIFT := "env -u TOOLCHAINS xcrun --toolchain default swift"

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
    -SNAPSHOT_TESTING_RECORD=all {{SWIFT}} test
    -just test-ios TEST_RUNNER_SNAPSHOT_TESTING_RECORD=all
    python3 {{PROJECT_ROOT}}/scripts/modules.py

# macOS doesn't scale text with Dynamic Type, so the large-text snapshots (under #if os(iOS)) run
# on an iOS simulator through xcodebuild. xcodebuild hands the test process only the variables
# prefixed TEST_RUNNER_, which is how record-snapshots asks it to record. The renderer draws at a
# fixed width and scale, so any simulator gives the same references.
IOS_DESTINATION := env("IOS_DESTINATION", "platform=iOS Simulator,name=iPad Pro 13-inch (M5)")

[doc('Run the SwiftPM tests on an iOS simulator (the Dynamic Type snapshots)')]
test-ios *env="":
    env {{env}} xcodebuild test -quiet -scheme DebugDrawer-Package -destination '{{IOS_DESTINATION}}' -derivedDataPath {{PROJECT_ROOT}}/.build/xcode-ios

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
    for module in $(python3 {{PROJECT_ROOT}}/scripts/modules.py platform-modules {{platform}}); do
        xcodebuild build -quiet -scheme "$module" -destination 'generic/platform={{platform}} Simulator' \
            -derivedDataPath {{PROJECT_ROOT}}/.build/xcode-{{lowercase(platform)}} SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
    done

[doc('Build the visionOS modules through SwiftPM for the visionOS simulator')]
spm-visionos: (spm-platform "visionOS")

[doc('Build the tvOS modules through SwiftPM for the tvOS simulator')]
spm-tvos: (spm-platform "tvOS")

[doc('Build the watchOS modules through SwiftPM for the watchOS simulator')]
spm-watchos: (spm-platform "watchOS")

# Package.swift's `.iOS` covers Mac Catalyst, so it is a destination rather than a platform.
[doc('Build the Mac Catalyst modules (CATALYST_MODULES in scripts/modules.py) through SwiftPM')]
spm-catalyst:
    #!/usr/bin/env bash
    set -euo pipefail
    for module in $(python3 {{PROJECT_ROOT}}/scripts/modules.py catalyst-modules); do
        xcodebuild build -quiet -scheme "$module" -destination 'generic/platform=macOS,variant=Mac Catalyst' \
            -derivedDataPath {{PROJECT_ROOT}}/.build/xcode-catalyst SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
    done

# The package holds every Example/iOS file and every example library and product their imports
# name, derived from the sources (scripts/catalyst_example.py); a file left out
# (CATALYST_EXAMPLE_EXCLUDE=Example/iOS/<file>) fails the build.
[doc('Build the iOS example as a Mac Catalyst app through SwiftPM, without launching it')]
spm-catalyst-example:
    python3 {{PROJECT_ROOT}}/scripts/catalyst_example.py build

[doc('Run the tests via SwiftPM')]
spm-test *args="":
    {{SWIFT}} test {{args}}

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

# The simulators `just run visionOS`, `just run tvOS` and `just run watchOS` boot, by name.
VISIONOS_DEVICE := env("VISIONOS_DEVICE", "Apple Vision Pro")
TVOS_DEVICE := env("TVOS_DEVICE", "Apple TV 4K (4th generation)")
WATCHOS_DEVICE := env("WATCHOS_DEVICE", "Apple Watch Series 12 (46mm)")

[doc('Build and launch an example app: just run, just run iOS, just run appkit, just run uikit, just run catalyst, just run visionOS, just run tvOS or just run watchOS')]
run target="macOS" *args="":
    #!/usr/bin/env bash
    set -euo pipefail
    # Builds an example app for a simulator, installs it from a writable copy (the simulator can't
    # copy Bazel's read-only bundle) and launches it. Extra arguments go to the app;
    # -OpenDebugDrawer opens the drawer at launch.
    run_in_simulator() {
        local target="$1" device="$2" bundle_id="$3" run_dir="$4"
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
        xcrun simctl install "$device" "$run_dir/DebugDrawerExample.app"
        xcrun simctl launch "$device" "$bundle_id" {{args}}
    }
    case "{{target}}" in
        macOS|macos)
            RUN_DIR="/tmp/debugdrawer-example"
            rm -rf "$RUN_DIR"
            mkdir -p "$RUN_DIR"
            {{BAZEL}} build //Example:ExampleApp_macOS
            APP_ZIP=$({{BAZEL}} cquery //Example:ExampleApp_macOS --output=files 2>/dev/null | grep '\.zip$')
            unzip -qo "$APP_ZIP" -d "$RUN_DIR"
            open "$RUN_DIR/DebugDrawerExample.app"
            ;;
        iOS|ios)
            {{BAZEL}} run //Example:ExampleApp_iOS
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
        catalyst|Catalyst)
            # The iOS example as a Mac Catalyst app, built through SwiftPM (Bazel has no Catalyst).
            python3 {{PROJECT_ROOT}}/scripts/catalyst_example.py build
            python3 {{PROJECT_ROOT}}/scripts/catalyst_example.py launch {{args}}
            ;;
        visionOS|visionos)
            run_in_simulator ExampleApp_visionOS "{{VISIONOS_DEVICE}}" com.debugdrawer.example.visionos \
                /tmp/debugdrawer-example-visionos
            ;;
        tvOS|tvos)
            run_in_simulator ExampleApp_tvOS "{{TVOS_DEVICE}}" com.debugdrawer.example.tvos \
                /tmp/debugdrawer-example-tvos
            ;;
        watchOS|watchos)
            run_in_simulator ExampleApp_watchOS "{{WATCHOS_DEVICE}}" com.debugdrawer.example.watchos \
                /tmp/debugdrawer-example-watchos
            ;;
        *)
            echo "Unknown target: {{target}}. Use 'macOS', 'iOS', 'appkit', 'uikit', 'catalyst', 'visionOS', 'tvOS' or 'watchOS'"
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
