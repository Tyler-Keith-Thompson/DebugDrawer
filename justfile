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

[doc('Re-resolve SwiftPM dependencies for Bazel after editing PACKAGES in scripts/modules.py')]
resolve:
    cd {{PROJECT_ROOT}}/swift && {{SWIFT}} package resolve

[doc('Build via SwiftPM too, to verify the published package (the Mac, then the visionOS modules)')]
spm:
    {{SWIFT}} build
    just spm-visionos

# `swift build` builds for the host only, so xcodebuild builds the modules ported to visionOS
# (VISIONOS_MODULES in scripts/modules.py) for its simulator, from the same Package.swift.
VISIONOS_BUILD_DESTINATION := "generic/platform=visionOS Simulator"

[doc('Build the visionOS modules through SwiftPM for the visionOS simulator')]
spm-visionos:
    #!/usr/bin/env bash
    set -euo pipefail
    for module in $(python3 {{PROJECT_ROOT}}/scripts/modules.py visionos-modules); do
        xcodebuild build -quiet -scheme "$module" -destination '{{VISIONOS_BUILD_DESTINATION}}' \
            -derivedDataPath {{PROJECT_ROOT}}/.build/xcode-visionos SWIFT_TREAT_WARNINGS_AS_ERRORS=YES
    done

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

# The simulator `just run visionOS` boots, by name.
VISIONOS_DEVICE := env("VISIONOS_DEVICE", "Apple Vision Pro")

[doc('Build and launch an example app: just run, just run iOS or just run visionOS')]
run target="macOS" *args="":
    #!/usr/bin/env bash
    set -euo pipefail
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
        visionOS|visionos)
            # Installed from a writable copy: the simulator can't copy Bazel's read-only bundle.
            # Extra arguments go to the app; -OpenDebugDrawer opens the drawer at launch.
            RUN_DIR="/tmp/debugdrawer-example-visionos"
            rm -rf "$RUN_DIR"
            mkdir -p "$RUN_DIR"
            {{BAZEL}} build //Example:ExampleApp_visionOS
            APP=$({{BAZEL}} cquery //Example:ExampleApp_visionOS --output=files 2>/dev/null | grep '\.app$')
            cp -RL "$APP" "$RUN_DIR/"
            chmod -R u+w "$RUN_DIR"
            xcrun simctl boot "{{VISIONOS_DEVICE}}" 2>/dev/null || true
            xcrun simctl bootstatus "{{VISIONOS_DEVICE}}" -b
            xcrun simctl install "{{VISIONOS_DEVICE}}" "$RUN_DIR/DebugDrawerExample.app"
            xcrun simctl launch "{{VISIONOS_DEVICE}}" com.debugdrawer.example.visionos {{args}}
            ;;
        *)
            echo "Unknown target: {{target}}. Use 'macOS', 'iOS' or 'visionOS'"
            exit 1
            ;;
    esac

[doc('Release a new version: verify, tag, push the tag and create the GitHub release, e.g. just deploy minor')]
deploy bump="patch":
    #!/usr/bin/env bash
    set -euo pipefail
    if [ -n "$(git status --porcelain)" ]; then
        echo "Error: working tree is dirty. Commit or stash changes first."
        exit 1
    fi
    # Every drawer entry point is #if DEBUG, so the tests run in debug; release must still build.
    just verify
    just release

    CURRENT=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || echo "")
    if [ -z "$CURRENT" ]; then
        NEW_VERSION="v0.0.1"
        echo "No existing version tags found. First release: ${NEW_VERSION}"
    else
        CURRENT="${CURRENT#v}"
        IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT"
        case "{{bump}}" in
            major) MAJOR=$((MAJOR + 1)); MINOR=0; PATCH=0 ;;
            minor) MINOR=$((MINOR + 1)); PATCH=0 ;;
            patch) PATCH=$((PATCH + 1)) ;;
            *) echo "Unknown bump: {{bump}}. Use major, minor, or patch."; exit 1 ;;
        esac
        NEW_VERSION="v${MAJOR}.${MINOR}.${PATCH}"
        echo "Current: v${CURRENT}"
        echo "    New: ${NEW_VERSION}"
    fi
    git tag -a "${NEW_VERSION}" -m "Release ${NEW_VERSION}"
    git push origin main --tags
    gh release create "${NEW_VERSION}" --title "${NEW_VERSION}" --generate-notes
    echo "Released ${NEW_VERSION}: $(gh repo view --json url -q .url)/releases/tag/${NEW_VERSION}"

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
    rm -rf {{PROJECT_ROOT}}/.build

[doc('Print the dependency graph of a target')]
deps target="//Sources/DebugDrawer":
    {{BAZEL}} query 'deps({{target}})' --output=label_kind

[doc('List every buildable target')]
targets:
    {{BAZEL}} query '//...' --output=label_kind
