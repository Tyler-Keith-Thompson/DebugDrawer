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

[doc('Build every target')]
build:
    {{BAZEL}} build //...

[doc('Run every test')]
test:
    {{BAZEL}} test //...

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

[doc('Build via SwiftPM too, to verify the published package')]
spm:
    {{SWIFT}} build

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

[doc('Build and launch an example app: just run, or just run iOS')]
run target="macOS":
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
        *)
            echo "Unknown target: {{target}}. Use 'macOS' or 'iOS'"
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
