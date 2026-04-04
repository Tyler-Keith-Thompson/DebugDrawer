PROJECT_ROOT := justfile_directory()
BAZEL_CONFIG := "debug"

[doc('Build all libraries')]
build:
    bazel build //Sources/... --config={{BAZEL_CONFIG}}

[doc('Run all tests')]
test:
    bazel test --config={{BAZEL_CONFIG}} //...

[doc('Build and run example app')]
run:
    #!/usr/bin/env bash
    set -euo pipefail
    RUN_DIR="/tmp/debugdrawer-example"
    rm -rf "$RUN_DIR"
    mkdir -p "$RUN_DIR"
    bazel build //Example:ExampleApp --config={{BAZEL_CONFIG}}
    APP_ZIP=$(bazel cquery //Example:ExampleApp --config={{BAZEL_CONFIG}} --output=files 2>/dev/null | grep '\.zip$')
    unzip -qo "$APP_ZIP" -d "$RUN_DIR"
    open "$RUN_DIR/DebugDrawerExample.app"

[doc('Clean build artifacts')]
clean:
    bazel clean

[doc('Build with SPM (verify Package.swift)')]
build-spm:
    swift build

[doc('Test with SPM')]
test-spm:
    swift test
