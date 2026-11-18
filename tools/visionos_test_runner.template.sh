#!/bin/bash
# Runs a visionOS unit test bundle (visionos_test_runner.bzl): a new simulator on the newest
# visionOS runtime, booted, the bundle run by the platform's xctest agent, the simulator deleted.
# `--test_filter` is not passed on: the bundle runs whole.

set -euo pipefail

if [[ -n "${TEST_PREMATURE_EXIT_FILE:-}" ]]; then
  touch "$TEST_PREMATURE_EXIT_FILE"
fi

test_bundle_path="%(test_bundle_path)s"
test_bundle_name=$(basename "$test_bundle_path")
test_bundle_name="${test_bundle_name%.*}"

work_dir="$(mktemp -d "${TEST_TMPDIR:-${TMPDIR:-/tmp}}/visionos_test.XXXXXX")"
simulator_id=""
clean_up() {
  if [[ -n "$simulator_id" ]]; then
    # Deleting a booted simulator shuts it down first.
    xcrun simctl delete "$simulator_id" >/dev/null 2>&1 || true
  fi
  rm -rf "$work_dir"
}
trap clean_up EXIT
# Bazel ends a test that runs out of time with SIGTERM, which skips the EXIT trap unless handled.
trap 'exit 143' TERM INT

if [[ "$test_bundle_path" == *.xctest ]]; then
  cp -cRL "$test_bundle_path" "$work_dir"
else
  unzip -qq -d "$work_dir" "$test_bundle_path"
fi
# Bazel's outputs are read-only, and the agent writes beside the bundle.
chmod -R u+w "$work_dir"

# The newest visionOS runtime installed and the device type to create on it.
read -r runtime device_type < <(xcrun simctl list runtimes --json | /usr/bin/python3 -c '
import json, sys
wanted = sys.argv[1]
runtimes = [r for r in json.load(sys.stdin)["runtimes"] if r.get("platform") == "xrOS" and r["isAvailable"]]
if not runtimes:
    sys.exit("error: no visionOS simulator runtime is installed (Xcode > Settings > Components)")
runtime = max(runtimes, key=lambda r: [int(part) for part in r["version"].split(".")])
types = [t["identifier"] for t in runtime["supportedDeviceTypes"]]
if wanted and wanted not in types:
    sys.exit("error: the visionOS " + runtime["version"] + " runtime supports no device type " + wanted)
print(runtime["identifier"], wanted or types[0])
' "%(device_type)s")

simulator_id=$(xcrun simctl create "Bazel $test_bundle_name $$" "$device_type" "$runtime")
xcrun simctl bootstatus "$simulator_id" -b >/dev/null

# The test environment (`--test_env`, the rule's `env`) and Bazel's own variables reach the
# process in the simulator through simctl's SIMCTL_CHILD_ prefix.
child_env=(
  "SIMCTL_CHILD_TEST_SRCDIR=${TEST_SRCDIR:-}"
  "SIMCTL_CHILD_TEST_UNDECLARED_OUTPUTS_DIR=${TEST_UNDECLARED_OUTPUTS_DIR:-}"
)
test_env="%(test_env)s"
if [[ -n "$test_env" ]]; then
  IFS="," read -r -a pairs <<< "$test_env"
  for pair in "${pairs[@]}"; do
    child_env+=("SIMCTL_CHILD_$pair")
  done
fi

developer_dir="$(xcode-select -p)/Platforms/XRSimulator.platform/Developer"
test_log="$work_dir/test.log"
test_exit_code=0
env "${child_env[@]}" \
  SIMCTL_CHILD_DYLD_LIBRARY_PATH="$developer_dir/usr/lib" \
  SIMCTL_CHILD_DYLD_FALLBACK_FRAMEWORK_PATH="$developer_dir/Library/Frameworks" \
  xcrun simctl spawn "$simulator_id" \
  "$developer_dir/Library/Xcode/Agents/xctest" \
  -XCTest All \
  "$work_dir/$test_bundle_name.xctest" \
  2>&1 | tee -i "$test_log" || test_exit_code=$?

if [[ "$test_exit_code" -ne 0 ]]; then
  echo "error: tests exited with $test_exit_code" >&2
  exit "$test_exit_code"
fi

# A crash after the last test reports success, and a bundle that held no tests runs nothing.
if grep -q -e "^Fatal error:" -e "^.*:[0-9]\+:\sFatal error:" "$test_log"; then
  echo "error: the log holds a fatal error" >&2
  exit 1
fi
if ! grep -q -E "Test run with [1-9][0-9]* tests?.* passed" "$test_log"; then
  echo "error: no Swift Testing run passed; is the bundle empty?" >&2
  exit 1
fi

if [[ -n "${TEST_PREMATURE_EXIT_FILE:-}" ]]; then
  rm -f "$TEST_PREMATURE_EXIT_FILE"
fi
