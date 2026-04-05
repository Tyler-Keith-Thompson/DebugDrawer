PROJECT_ROOT := justfile_directory()
BAZEL_CONFIG := "debug"

[doc('Build all libraries')]
build:
    bazel build //Sources/... --config={{BAZEL_CONFIG}}

[doc('Run all tests')]
test:
    bazel test --config={{BAZEL_CONFIG}} //...

[doc('Build and run macOS example app')]
run target="macOS":
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{target}}" in
        macOS|macos)
            RUN_DIR="/tmp/debugdrawer-example"
            rm -rf "$RUN_DIR"
            mkdir -p "$RUN_DIR"
            bazel build //Example:ExampleApp_macOS --config={{BAZEL_CONFIG}}
            APP_ZIP=$(bazel cquery //Example:ExampleApp_macOS --config={{BAZEL_CONFIG}} --output=files 2>/dev/null | grep '\.zip$')
            unzip -qo "$APP_ZIP" -d "$RUN_DIR"
            open "$RUN_DIR/DebugDrawerExample.app"
            ;;
        iOS|ios)
            bazel run //Example:ExampleApp_iOS --config={{BAZEL_CONFIG}}
            ;;
        *)
            echo "Unknown target: {{target}}. Use 'macOS' or 'iOS'"
            exit 1
            ;;
    esac

[doc('Generate Xcode project (pass --no-open to skip opening)')]
generate *args:
    #!/usr/bin/env bash
    set -euo pipefail
    OPEN=true
    for arg in {{args}}; do
        case "$arg" in
            --no-open) OPEN=false ;;
            *) echo "Unknown arg: $arg"; exit 1 ;;
        esac
    done
    echo "Generating Xcode project..."
    bazel run //:xcodeproj
    chmod -R u+w DebugDrawer.xcodeproj
    if [ "$OPEN" = true ]; then
        echo "Opening DebugDrawer.xcodeproj..."
        open DebugDrawer.xcodeproj
    else
        echo "Done. Open DebugDrawer.xcodeproj"
    fi

[doc('Deploy a new release: test, tag, push')]
deploy bump="patch":
    #!/usr/bin/env bash
    set -euo pipefail

    # Ensure clean working tree
    if [ -n "$(git status --porcelain)" ]; then
        echo "Error: working tree is dirty. Commit or stash changes first."
        exit 1
    fi

    # Run all tests (Bazel + SPM)
    echo "Running Bazel tests..."
    bazel test --config=release //...
    echo "Running SPM tests..."
    swift test

    # Get current version
    CURRENT=$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null || echo "")
    if [ -z "$CURRENT" ]; then
        # No tags yet — first release
        NEW_VERSION="v0.0.1"
        echo ""
        echo "No existing version tags found. First release."
        echo "    New: ${NEW_VERSION}"
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
        echo ""
        echo "Current: v${CURRENT}"
        echo "    New: ${NEW_VERSION}"
    fi
    echo ""
    read -p "Tag and push ${NEW_VERSION}? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 1
    fi

    git tag -a "${NEW_VERSION}" -m "Release ${NEW_VERSION}"
    git push origin main --tags

    # Create GitHub release
    echo "Creating GitHub release..."
    gh release create "${NEW_VERSION}" \
        --title "${NEW_VERSION}" \
        --generate-notes

    VERSION_NUM="${NEW_VERSION#v}"
    echo ""
    echo "Released ${NEW_VERSION}"
    echo "GitHub: $(gh repo view --json url -q .url)/releases/tag/${NEW_VERSION}"
    echo "SPM:    .package(url: \"...\", from: \"${VERSION_NUM}\")"

[doc('Clean build artifacts')]
clean:
    bazel clean

[doc('Build with SPM (verify Package.swift)')]
build-spm:
    swift build

[doc('Test with SPM')]
test-spm:
    swift test
