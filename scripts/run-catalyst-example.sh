#!/usr/bin/env bash
# Build the iOS example app (Example/iOS) as a Mac Catalyst app and launch it in the background.
#
# Usage:
#   ./scripts/run-catalyst-example.sh [app arguments...]   # e.g. -OpenDebugDrawer
#
# Bazel has no Mac Catalyst platform (tools/catalyst.bzl), so SwiftPM builds it: a throwaway
# package under .build/catalyst-example holds the example's sources as an executable target that
# depends on this package's products, xcodebuild builds it for Mac Catalyst, and the executable is
# wrapped in an ad-hoc signed .app bundle with Example/iOS's identity, as Xcode would for a
# Catalyst app.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
work="$root/.build/catalyst-example"
products="$work/DerivedData/Build/Products/Debug-maccatalyst"
app="$work/DebugDrawerExample.app"

mkdir -p "$work/Sources/ExampleApp_iOS"
ln -sf "$root/Example/iOS/ExampleApp_iOS.swift" "$work/Sources/ExampleApp_iOS/ExampleApp_iOS.swift"

# The products the example imports, from its own import lines.
dependencies=$(sed -n 's/^import \(DebugDrawer[A-Za-z]*\)$/            .product(name: "\1", package: "DebugDrawer"),/p' \
    "$root/Example/iOS/ExampleApp_iOS.swift")
cat > "$work/Package.swift" <<EOF
// swift-tools-version: 6.3
// Written by scripts/run-catalyst-example.sh.
import PackageDescription

let package = Package(
    name: "CatalystExample",
    platforms: [.iOS(.v17), .macOS(.v15)],
    dependencies: [.package(name: "DebugDrawer", path: "$root")],
    targets: [
        .executableTarget(name: "ExampleApp_iOS", dependencies: [
$dependencies
        ]),
    ]
)
EOF

# Not SWIFT_TREAT_WARNINGS_AS_ERRORS: it would apply to OSLogClient, which builds with warnings
# suppressed. `just build-spm` holds the libraries to that.
(cd "$work" && xcodebuild build -quiet -scheme CatalystExample \
    -destination 'platform=macOS,variant=Mac Catalyst' -derivedDataPath "$work/DerivedData")

rm -rf "$app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$products/ExampleApp_iOS" "$app/Contents/MacOS/"
cp -R "$products/"*.bundle "$app/Contents/Resources/"
plist="$app/Contents/Info.plist"
cp "$root/Example/iOS/Info.plist" "$plist"
plutil -insert CFBundleExecutable -string ExampleApp_iOS "$plist"
plutil -insert CFBundleSupportedPlatforms -json '["MacOSX"]' "$plist"
# The iPad idiom: Catalyst's "Scaled to match iPad".
plutil -insert UIDeviceFamily -json '[2]' "$plist"
codesign --force --sign - "$app"

# -g keeps the app behind the frontmost one; -n starts a new instance each run.
open -g -n "$app" --args "$@"
echo "Launched $app"
