#!/usr/bin/env python3
"""Finds the iPhone and the provisioning profile `just run device` installs the iOS example with.

Usage:
    python3 scripts/device_example.py check    # prints the device's UDID, or why it can't

The iOS example (//Example:ExampleApp_iOS) builds for a device with `--define=example_device=true`,
which signs it with the profile Xcode's automatic signing makes for its bundle ID
(Example/BUILD.bazel's local_provisioning_profile) and its device entitlements. Before building,
`check` makes sure both things the build and install need are there, and names the missing setup
when one isn't:

- a profile named PROFILE_NAME, unexpired, in Xcode's or MobileDevice's profile folder, that
  provisions the device (or every device);
- a physical iPhone or iPad paired with this Mac and reachable (devicectl's "available"). With
  several, DEBUGDRAWER_DEVICE (a name or UDID) picks one, else the first is used.
"""

import datetime
import glob
import json
import os
import plistlib
import subprocess
import sys
import tempfile

BUNDLE_ID = "com.debugdrawer.example.ios"
APP_GROUP = "group.com.debugdrawer.example"
PROFILE_NAME = f"iOS Team Provisioning Profile: {BUNDLE_ID}"
DEVICE_VARIABLE = "DEBUGDRAWER_DEVICE"
PROFILE_DIRECTORIES = [
    "~/Library/Developer/Xcode/UserData/Provisioning Profiles",
    "~/Library/MobileDevice/Provisioning Profiles",
]

NO_DEVICE = (
    "No iPhone or iPad is paired with this Mac and reachable. Connect one by cable (or on the same "
    "network, with Developer Mode on), trust this Mac on it, then check that "
    "`xcrun devicectl list devices` lists it as available (paired)."
)


def missing_profile(udid):
    return (
        f'No provisioning profile "{PROFILE_NAME}" that is unexpired and provisions device {udid}. '
        "One-time setup in Xcode: File > New > Project > iOS App, any name, Team: your team, "
        f"Bundle Identifier: {BUNDLE_ID}. In Signing & Capabilities keep Automatically manage "
        f"signing on and add App Groups ({APP_GROUP}) and Push Notifications. Pick the iPhone as "
        "the run destination and build once (Product > Build). Xcode registers the App ID, the app "
        "group and the device in your team and saves the profile. The project can be deleted "
        "afterwards."
    )


class SetupError(Exception):
    """What the Mac is missing before the example can be installed on a device."""


def reachable_devices(devicectl_json):
    """(name, UDID) of each physical iPhone or iPad `devicectl list devices --json-output` lists
    as paired and reachable, in its order."""
    devices = []
    for device in devicectl_json.get("result", {}).get("devices", []):
        hardware = device.get("hardwareProperties", {})
        connection = device.get("connectionProperties", {})
        if hardware.get("reality") != "physical" or hardware.get("platform") != "iOS":
            continue
        # devicectl shows "available (paired)" for a paired device whose tunnel isn't up yet
        # ("disconnected") or is ("connected"); "unavailable" is one it can't reach.
        if connection.get("pairingState") != "paired" or connection.get("tunnelState") == "unavailable":
            continue
        devices.append((device.get("deviceProperties", {}).get("name", ""), hardware.get("udid", "")))
    return devices


def choose_device(devices, requested):
    """The UDID of the device `requested` names (a name or UDID), or of the first when it is empty.

    Raises SetupError when there is none, or none by that name.
    """
    if not devices:
        raise SetupError(NO_DEVICE)
    if not requested:
        return devices[0][1]
    for name, udid in devices:
        if requested in (name, udid):
            return udid
    listed = ", ".join(f"{name} ({udid})" for name, udid in devices)
    raise SetupError(f"{DEVICE_VARIABLE} is {requested}, which names none of the reachable devices: {listed}.")


def provisions(profile, udid, now):
    """Whether `profile` (a decoded provisioning profile) is the example's, unexpired, for `udid`."""
    if profile.get("Name") != PROFILE_NAME:
        return False
    expiration = profile.get("ExpirationDate")
    if expiration is None or expiration.replace(tzinfo=datetime.timezone.utc) <= now:
        return False
    return profile.get("ProvisionsAllDevices", False) or udid in profile.get("ProvisionedDevices", [])


def check_profile(profiles, udid, now):
    """Raises SetupError unless one of `profiles` provisions `udid` for the example."""
    if not any(provisions(profile, udid, now) for profile in profiles):
        raise SetupError(missing_profile(udid))


def installed_profiles():
    """Every provisioning profile in Xcode's and MobileDevice's folders, decoded."""
    profiles = []
    for directory in PROFILE_DIRECTORIES:
        for path in sorted(glob.glob(os.path.join(os.path.expanduser(directory), "*.mobileprovision"))):
            decoded = subprocess.run(["security", "cms", "-D", "-i", path], capture_output=True, check=False)
            if decoded.returncode == 0:
                profiles.append(plistlib.loads(decoded.stdout))
    return profiles


def listed_devices():
    with tempfile.TemporaryDirectory() as directory:
        output = os.path.join(directory, "devices.json")
        subprocess.run(
            ["xcrun", "devicectl", "list", "devices", "--json-output", output],
            capture_output=True, check=False,
        )
        if not os.path.exists(output):
            return {}
        with open(output, encoding="utf-8") as file:
            return json.load(file)


def main(arguments):
    if arguments != ["check"]:
        print(__doc__, file=sys.stderr)
        return 2
    try:
        udid = choose_device(reachable_devices(listed_devices()), os.environ.get(DEVICE_VARIABLE, ""))
        check_profile(installed_profiles(), udid, datetime.datetime.now(datetime.timezone.utc))
    except SetupError as error:
        print(f"error: {error}", file=sys.stderr)
        return 1
    print(udid)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
