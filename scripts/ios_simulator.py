#!/usr/bin/env python3
"""The iOS simulator `just test-ios` runs on: one per checkout, so two checkouts can test at once.

Usage:
    python3 scripts/ios_simulator.py udid    # this checkout's simulator, made on first use, after a prune
    python3 scripts/ios_simulator.py delete  # delete this checkout's simulator
    python3 scripts/ios_simulator.py prune   # delete the simulators of checkouts that are gone

Two xcodebuild runs on one simulator install and launch their test hosts over each other, so a
run started from a second worktree could fail the first. Each checkout gets a simulator of its
own instead, named after the checkout's path (NAME_PREFIX plus the path), which later runs reuse.
It is the model the snapshots are recorded on (MODEL), on the newest iOS runtime that has it,
which is the one `name=<MODEL>` picks. When a newer runtime arrives, or the simulator's runtime
goes away, the next run deletes it and makes another.

Only simulators whose name starts with NAME_PREFIX are ever deleted, and only through
`xcrun simctl delete`. `prune` deletes those whose checkout no longer exists, such as a removed
worktree's, and `udid` deletes them too before it picks this checkout's, so each `just test-ios`
clears away the simulators of the worktrees removed since the last one.
"""

import json
import os
import subprocess
import sys

ROOT = os.path.realpath(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
MODEL = "iPad Pro 13-inch (M5)"
NAME_PREFIX = "DebugDrawer test-ios: "


def device_name(root):
    return NAME_PREFIX + root


def checkout_of(name):
    """The checkout a simulator was made for, or None when it isn't one of ours."""
    return name[len(NAME_PREFIX):] if name.startswith(NAME_PREFIX) else None


def version_key(runtime):
    return tuple(int(part) for part in runtime["version"].split(".") if part.isdigit())


def newest_runtime(runtimes, model=MODEL):
    """The (runtime, device type) identifiers of the newest available iOS runtime with the model."""
    candidates = []
    for runtime in runtimes["runtimes"]:
        if runtime.get("platform") != "iOS" or not runtime.get("isAvailable"):
            continue
        for device_type in runtime.get("supportedDeviceTypes", []):
            if device_type["name"] == model:
                candidates.append((version_key(runtime), runtime["identifier"], device_type["identifier"]))
    if not candidates:
        raise SystemExit(f"No installed iOS runtime has the {model}: install one in Xcode's Components settings")
    _, runtime, device_type = max(candidates)
    return runtime, device_type


def ours(devices, name):
    """(runtime, device) for each simulator called `name`."""
    return [(runtime, device) for runtime, listed in devices["devices"].items() for device in listed if device["name"] == name]


def plan(devices, name, runtime, exists=os.path.isdir):
    """(the simulator to reuse or None, the simulators to delete) for this checkout's `name`.

    The simulators to delete are this checkout's that can't be reused, then every one `gone` names.
    """
    reuse = None
    stale = []
    for device_runtime, device in ours(devices, name):
        if reuse is None and device_runtime == runtime and device.get("isAvailable", False):
            reuse = device["udid"]
        else:
            stale.append(device["udid"])
    pruned = [udid for udid in gone(devices, exists) if udid != reuse and udid not in stale]
    return reuse, stale + pruned


def gone(devices, exists=os.path.isdir):
    """The simulators made for a checkout that no longer exists."""
    return [
        device["udid"]
        for listed in devices["devices"].values()
        for device in listed
        if (checkout := checkout_of(device["name"])) is not None and not exists(checkout)
    ]


def simctl(*arguments):
    return subprocess.run(["xcrun", "simctl", *arguments], check=True, capture_output=True, text=True).stdout


def listing(kind):
    return json.loads(simctl("list", kind, "-j"))


def delete(udid):
    # A booted simulator is shut down first; one already shut down makes shutdown fail, harmlessly.
    subprocess.run(["xcrun", "simctl", "shutdown", udid], capture_output=True)
    simctl("delete", udid)
    print(f"Deleted simulator {udid}", file=sys.stderr)


def main(arguments):
    command = arguments[0] if arguments else ""
    name = device_name(ROOT)
    if command == "udid":
        runtime, device_type = newest_runtime(listing("runtimes"))
        reuse, stale = plan(listing("devices"), name, runtime)
        for udid in stale:
            delete(udid)
        if reuse is None:
            reuse = simctl("create", name, device_type, runtime).strip()
            print(f"Made simulator {reuse} ({MODEL}, {runtime}) for {ROOT}", file=sys.stderr)
        print(reuse)
    elif command == "delete":
        for _, device in ours(listing("devices"), name):
            delete(device["udid"])
    elif command == "prune":
        for udid in gone(listing("devices")):
            delete(udid)
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
