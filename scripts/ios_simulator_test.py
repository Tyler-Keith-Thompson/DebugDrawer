"""Tests of how scripts/ios_simulator.py picks the simulator `just test-ios` runs on: one per
checkout, the snapshots' model on the newest runtime that has it, replaced when that runtime
changes, and only its own simulators ever deleted."""

import importlib.machinery
import importlib.util
import os
import unittest

RUNFILES = os.getcwd()
SCRIPT = os.path.join(RUNFILES, "scripts", "ios_simulator.py")

loader = importlib.machinery.SourceFileLoader("ios_simulator", SCRIPT)
specification = importlib.util.spec_from_loader("ios_simulator", loader)
ios_simulator = importlib.util.module_from_spec(specification)
loader.exec_module(ios_simulator)

M5 = {"name": "iPad Pro 13-inch (M5)", "identifier": "iPad-Pro-13-inch-M5-12GB"}
M5_16GB = {"name": "iPad Pro 13-inch (M5) (16GB)", "identifier": "iPad-Pro-13-inch-M5-16GB"}
IPHONE = {"name": "iPhone 17", "identifier": "iPhone-17"}


def runtime(identifier, version, types, platform="iOS", available=True):
    return {"identifier": identifier, "version": version, "platform": platform, "isAvailable": available, "supportedDeviceTypes": types}


def device(name, udid, available=True):
    return {"name": name, "udid": udid, "isAvailable": available}


class RuntimeTests(unittest.TestCase):
    def test_the_newest_available_ios_runtime_with_the_model(self):
        runtimes = {"runtimes": [
            runtime("iOS-26-2", "26.2", [M5_16GB, IPHONE]),
            runtime("iOS-27-2", "27.2", [M5_16GB, M5]),
            runtime("iOS-27-10", "27.10", [M5], available=False),
            runtime("iOS-28-0", "28.0", [IPHONE]),
            runtime("visionOS-27-2", "27.2", [M5], platform="visionOS"),
            runtime("iOS-27-1", "27.1", [M5]),
        ]}

        actual = ios_simulator.newest_runtime(runtimes)

        self.assertEqual(actual, ("iOS-27-2", "iPad-Pro-13-inch-M5-12GB"))

    def test_versions_compare_as_numbers(self):
        runtimes = {"runtimes": [runtime("iOS-27-9", "27.9", [M5]), runtime("iOS-27-10", "27.10", [M5])]}

        actual = ios_simulator.newest_runtime(runtimes)

        self.assertEqual(actual[0], "iOS-27-10")

    def test_no_runtime_with_the_model_says_so(self):
        runtimes = {"runtimes": [runtime("iOS-27-2", "27.2", [IPHONE])]}

        with self.assertRaises(SystemExit) as raised:
            ios_simulator.newest_runtime(runtimes)

        self.assertIn("iPad Pro 13-inch (M5)", str(raised.exception))


class PlanTests(unittest.TestCase):
    NAME = ios_simulator.device_name("/work/DebugDrawer")

    def test_reuses_this_checkouts_simulator_and_leaves_every_other(self):
        devices = {"devices": {
            "iOS-27-2": [
                device("iPad Pro 13-inch (M5)", "OWNER"),
                device(self.NAME, "MINE"),
                device(ios_simulator.device_name("/work/Other"), "OTHER"),
            ],
        }}

        actual = ios_simulator.plan(devices, self.NAME, "iOS-27-2", exists=lambda path: True)

        self.assertEqual(actual, ("MINE", []))

    def test_makes_one_when_this_checkout_has_none(self):
        devices = {"devices": {"iOS-27-2": [device("iPad Pro 13-inch (M5)", "OWNER")]}}

        actual = ios_simulator.plan(devices, self.NAME, "iOS-27-2", exists=lambda path: True)

        self.assertEqual(actual, (None, []))

    def test_replaces_one_on_an_older_or_missing_runtime(self):
        devices = {"devices": {
            "iOS-27-1": [device(self.NAME, "OLDER")],
            "iOS-27-2": [device(self.NAME, "BROKEN", available=False)],
        }}

        actual = ios_simulator.plan(devices, self.NAME, "iOS-27-2", exists=lambda path: True)

        self.assertEqual(actual, (None, ["OLDER", "BROKEN"]))

    def test_keeps_one_of_two_on_the_runtime(self):
        devices = {"devices": {"iOS-27-2": [device(self.NAME, "FIRST"), device(self.NAME, "SECOND")]}}

        actual = ios_simulator.plan(devices, self.NAME, "iOS-27-2", exists=lambda path: True)

        self.assertEqual(actual, ("FIRST", ["SECOND"]))

    def test_also_deletes_the_simulators_of_checkouts_that_are_gone(self):
        devices = {"devices": {
            "iOS-27-2": [
                device("iPad Pro 13-inch (M5)", "OWNER"),
                device(self.NAME, "MINE"),
                device(ios_simulator.device_name("/work/kept"), "KEPT"),
                device(ios_simulator.device_name("/work/removed"), "REMOVED"),
            ],
            "iOS-27-1": [device(self.NAME, "OLDER")],
        }}
        kept = {"/work/DebugDrawer", "/work/kept"}

        actual = ios_simulator.plan(devices, self.NAME, "iOS-27-2", exists=lambda path: path in kept)

        self.assertEqual(actual, ("MINE", ["OLDER", "REMOVED"]))


class PruneTests(unittest.TestCase):
    def test_deletes_only_ours_whose_checkout_is_gone(self):
        devices = {"devices": {
            "iOS-27-2": [
                device("iPad Pro 13-inch (M5)", "OWNER"),
                device("DebugDrawer", "OWNER_NAMED_LIKE_US"),
                device(ios_simulator.device_name("/work/kept"), "KEPT"),
                device(ios_simulator.device_name("/work/removed"), "REMOVED"),
            ],
            "iOS-26-2": [device(ios_simulator.device_name("/work/removed-too"), "REMOVED_TOO")],
        }}

        actual = ios_simulator.gone(devices, exists=lambda path: path == "/work/kept")

        self.assertEqual(sorted(actual), ["REMOVED", "REMOVED_TOO"])

    def test_the_name_round_trips_to_its_checkout(self):
        actual = ios_simulator.checkout_of(ios_simulator.device_name("/work/a b/DebugDrawer"))

        self.assertEqual(actual, "/work/a b/DebugDrawer")


if __name__ == "__main__":
    unittest.main()
