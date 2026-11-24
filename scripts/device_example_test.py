"""Tests of how scripts/device_example.py finds the iPhone `just run device` installs the iOS
example on, and the provisioning profile it is signed with, and how it names the missing setup."""

import datetime
import importlib.machinery
import importlib.util
import os
import unittest

RUNFILES = os.getcwd()
SCRIPT = os.path.join(RUNFILES, "scripts", "device_example.py")

loader = importlib.machinery.SourceFileLoader("device_example", SCRIPT)
specification = importlib.util.spec_from_loader("device_example", loader)
device_example = importlib.util.module_from_spec(specification)
loader.exec_module(device_example)

NOW = datetime.datetime(2026, 11, 24, tzinfo=datetime.timezone.utc)
PHONE = "00008160-0009306A0A200036"
OTHER_PHONE = "00008150-001428681ED8401C"


def device(name, udid, reality="physical", platform="iOS", pairing="paired", tunnel="disconnected"):
    return {
        "deviceProperties": {"name": name},
        "hardwareProperties": {"udid": udid, "reality": reality, "platform": platform},
        "connectionProperties": {"pairingState": pairing, "tunnelState": tunnel},
    }


def listing(*devices):
    return {"result": {"devices": list(devices)}}


def profile(name=device_example.PROFILE_NAME, expires=datetime.datetime(2027, 11, 24), devices=(PHONE,), all_devices=False):
    decoded = {"Name": name, "ExpirationDate": expires, "ProvisionedDevices": list(devices)}
    if all_devices:
        decoded["ProvisionsAllDevices"] = True
    return decoded


class ReachableDevicesTests(unittest.TestCase):
    def test_a_paired_physical_iphone_is_reachable_whether_or_not_its_tunnel_is_up(self):
        expected = [("Phone", PHONE), ("Other", OTHER_PHONE)]

        actual = device_example.reachable_devices(listing(
            device("Phone", PHONE, tunnel="disconnected"), device("Other", OTHER_PHONE, tunnel="connected")
        ))

        self.assertEqual(actual, expected)

    def test_simulators_unpaired_unreachable_and_other_platforms_are_left_out(self):
        expected = []

        actual = device_example.reachable_devices(listing(
            device("Simulator", "SIM", reality="simulated"),
            device("Unpaired", "UNPAIRED", pairing="unpaired"),
            device("Away", "AWAY", tunnel="unavailable"),
            device("Watch", "WATCH", platform="watchOS"),
        ))

        self.assertEqual(actual, expected)

    def test_an_empty_or_failed_listing_has_no_devices(self):
        self.assertEqual(device_example.reachable_devices({}), [])


class ChooseDeviceTests(unittest.TestCase):
    def test_without_a_request_the_first_device_is_chosen(self):
        actual = device_example.choose_device([("Phone", PHONE), ("Other", OTHER_PHONE)], "")

        self.assertEqual(actual, PHONE)

    def test_a_request_picks_a_device_by_name_or_udid(self):
        devices = [("Phone", PHONE), ("Other", OTHER_PHONE)]

        by_name = device_example.choose_device(devices, "Other")
        by_udid = device_example.choose_device(devices, OTHER_PHONE)

        self.assertEqual(by_name, OTHER_PHONE)
        self.assertEqual(by_udid, OTHER_PHONE)

    def test_no_reachable_device_names_the_pairing_setup(self):
        with self.assertRaises(device_example.SetupError) as raised:
            device_example.choose_device([], "")

        self.assertIn("xcrun devicectl list devices", str(raised.exception))

    def test_a_request_naming_no_reachable_device_lists_the_ones_there_are(self):
        with self.assertRaises(device_example.SetupError) as raised:
            device_example.choose_device([("Phone", PHONE)], "iPad")

        self.assertIn(device_example.DEVICE_VARIABLE, str(raised.exception))
        self.assertIn(f"Phone ({PHONE})", str(raised.exception))


class CheckProfileTests(unittest.TestCase):
    def test_the_examples_unexpired_profile_for_the_device_passes(self):
        device_example.check_profile([profile(name="iOS Team Provisioning Profile: other"), profile()], PHONE, NOW)

    def test_a_profile_for_every_device_passes(self):
        device_example.check_profile([profile(devices=(), all_devices=True)], PHONE, NOW)

    def test_no_profile_names_the_xcode_setup_with_the_bundle_id_and_app_group(self):
        with self.assertRaises(device_example.SetupError) as raised:
            device_example.check_profile([], PHONE, NOW)

        message = str(raised.exception)
        self.assertIn(device_example.PROFILE_NAME, message)
        self.assertIn(device_example.BUNDLE_ID, message)
        self.assertIn(device_example.APP_GROUP, message)
        self.assertIn("Push Notifications", message)

    def test_an_expired_profile_or_one_without_the_device_fails(self):
        cases = [
            profile(expires=datetime.datetime(2026, 11, 23)),
            profile(devices=(OTHER_PHONE,)),
            profile(name="iOS Team Provisioning Profile: com.example.other"),
        ]
        for case in cases:
            with self.subTest(case=case), self.assertRaises(device_example.SetupError):
                device_example.check_profile([case], PHONE, NOW)


if __name__ == "__main__":
    unittest.main()
