#!/bin/bash
# Creates and boots a new iOS simulator for one `ios_unit_test` run (//tools:ios_test_runner), and
# prints its UDID; the runner's cleanup action deletes it afterwards. rules_apple's own creator
# reuses a simulator named for the device and version even when `reuse_simulator` is off, so two
# runs at once (several worktrees, say) would share one, and the first to finish would delete it
# under the other. The name here is the run's own.
#
# The runner sets SIMULATOR_DEVICE_TYPE (a device type's name, "iPhone 17") and
# SIMULATOR_OS_VERSION ("27.2"); only the UDID goes to stdout, which the runner reads.

set -euo pipefail

runtime="com.apple.CoreSimulator.SimRuntime.iOS-${SIMULATOR_OS_VERSION//./-}"
simulator_id=$(xcrun simctl create "Bazel ${SIMULATOR_DEVICE_TYPE} $$-$RANDOM" "$SIMULATOR_DEVICE_TYPE" "$runtime")
if ! xcrun simctl bootstatus "$simulator_id" -b >&2; then
  xcrun simctl delete "$simulator_id" >&2 || true
  exit 1
fi
echo "$simulator_id"
