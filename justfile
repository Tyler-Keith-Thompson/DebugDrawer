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

[doc('Clean build artifacts')]
clean:
    bazel clean

[doc('Build with SPM (verify Package.swift)')]
build-spm:
    swift build

[doc('Test with SPM')]
test-spm:
    swift test
