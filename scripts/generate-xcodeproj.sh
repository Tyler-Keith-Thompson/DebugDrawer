#!/usr/bin/env bash
# Generate an Xcode project from the Bazel graph, via rules_xcodeproj.
#
# Usage:
#   ./scripts/generate-xcodeproj.sh             # generate and open
#   ./scripts/generate-xcodeproj.sh --no-open   # generate only
set -euo pipefail

OPEN=true
for arg in "$@"; do
    case "$arg" in
        --no-open) OPEN=false ;;
        *) echo "Unknown argument: $arg" >&2; exit 1 ;;
    esac
done

# Under xcode/, not the root (install_directory in BUILD.bazel): xcodebuild run in a directory that
# holds a .xcodeproj builds that project instead of Package.swift, which breaks every SwiftPM
# recipe that calls xcodebuild (test-ios, spm-platform, spm-catalyst...).
PROJECT="xcode/DebugDrawer.xcodeproj"

# A project generated at the root before it moved still breaks those recipes.
if [ -e "DebugDrawer.xcodeproj" ]; then
    echo "warning: DebugDrawer.xcodeproj at the root is left from an older \`just generate\`; delete it," >&2
    echo "         as xcodebuild builds it instead of Package.swift. The project is now ${PROJECT}." >&2
fi

mkdir -p "$(dirname "$PROJECT")"
echo "Generating ${PROJECT} from the Bazel graph..."
bazel run //:xcodeproj

# rules_xcodeproj marks generated files read-only, which stops Xcode writing scheme state.
chmod -R u+w "$PROJECT"

if [ "$OPEN" = true ]; then
    echo "Opening ${PROJECT}..."
    open "$PROJECT"
else
    echo "Done. Open ${PROJECT} when you want it."
fi
