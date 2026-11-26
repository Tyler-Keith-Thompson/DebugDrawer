#!/bin/bash
# The pre-action of //tools/ui_test:runner: before a UI test runs, removes from the simulator every
# app whose bundle is in the test's runfiles (its target app), so xcodebuild installs it fresh.
# The runner reuses a booted simulator, and installing over an earlier install keeps any file whose
# size and modification time match. Bazel gives every file the same fixed time, and a small change
# to the app's code rarely changes its binary's size (Mach-O segments are page-aligned), so without
# this the test can drive an earlier build of the app.
set -euo pipefail
: "${SIMULATOR_UDID:?the runner sets SIMULATOR_UDID}"

find -L . -name '*.ipa' -print0 | while IFS= read -r -d '' ipa; do
    # The app's own Info.plist, not one of its frameworks'.
    info_plist="$(unzip -Z1 "$ipa" | grep -E '^Payload/[^/]+\.app/Info\.plist$')"
    bundle_id="$(unzip -p "$ipa" "$info_plist" | plutil -extract CFBundleIdentifier raw -o - -)"
    # Succeeds when the app isn't installed, too.
    xcrun simctl uninstall "$SIMULATOR_UDID" "$bundle_id"
done
