"""Tests of how scripts/sign_example.py picks the identity `just run macOS` signs the example with:
the environment's when set, else the Keychain's Apple Development identity, else ad hoc with a
warning; and how --app-group names the group after the signing team."""

import importlib.machinery
import importlib.util
import os
import unittest

RUNFILES = os.getcwd()
SCRIPT = os.path.join(RUNFILES, "scripts", "sign_example.py")

loader = importlib.machinery.SourceFileLoader("sign_example", SCRIPT)
specification = importlib.util.spec_from_loader("sign_example", loader)
sign_example = importlib.util.module_from_spec(specification)
loader.exec_module(sign_example)

DEVELOPMENT = "2222222222222222222222222222222222222222"
RENEWED = "1111111111111111111111111111111111111111"
DEVELOPER_ID = "3333333333333333333333333333333333333333"

KEYCHAIN = f"""  1) {DEVELOPER_ID} "Developer ID Application: Example Developer (AAAAAAAAAA)"
  2) {DEVELOPMENT} "Apple Development: Example Developer (BBBBBBBBBB)"
  3) {RENEWED} "Apple Development: Example Developer (BBBBBBBBBB)"
     3 valid identities found
"""

EMPTY_KEYCHAIN = "     0 valid identities found\n"


def keychain(output):
    calls = []

    def find_identity():
        calls.append(True)
        return output

    return find_identity, calls


class ChooseTests(unittest.TestCase):
    def test_the_keychains_first_apple_development_identity_by_its_sha1(self):
        find_identity, _ = keychain(KEYCHAIN)

        actual = sign_example.choose({}, find_identity)

        self.assertEqual(actual, (DEVELOPMENT, None))

    def test_no_apple_development_identity_signs_ad_hoc_with_a_warning(self):
        find_identity, _ = keychain(f'  1) {DEVELOPER_ID} "Developer ID Application: Example Developer (AAAAAAAAAA)"\n')

        identity, warning = sign_example.choose({}, find_identity)

        self.assertEqual(identity, "-")
        self.assertIn("no Apple Development signing identity in the Keychain", warning)
        self.assertIn("signed ad hoc", warning)
        self.assertIn("DEBUGDRAWER_SIGN_IDENTITY", warning)

    def test_an_empty_keychain_signs_ad_hoc_with_a_warning(self):
        find_identity, _ = keychain(EMPTY_KEYCHAIN)

        identity, warning = sign_example.choose({}, find_identity)

        self.assertEqual(identity, "-")
        self.assertIsNotNone(warning)

    def test_the_environment_variable_wins_without_reading_the_keychain(self):
        find_identity, calls = keychain(KEYCHAIN)

        actual = sign_example.choose({"DEBUGDRAWER_SIGN_IDENTITY": DEVELOPER_ID}, find_identity)

        self.assertEqual(actual, (DEVELOPER_ID, None))
        self.assertEqual(calls, [])

    def test_a_dash_in_the_environment_forces_ad_hoc_with_a_warning(self):
        find_identity, calls = keychain(KEYCHAIN)

        identity, warning = sign_example.choose({"DEBUGDRAWER_SIGN_IDENTITY": "-"}, find_identity)

        self.assertEqual(identity, "-")
        self.assertIn("DEBUGDRAWER_SIGN_IDENTITY is -", warning)
        self.assertIn("signed ad hoc", warning)
        self.assertEqual(calls, [])

    def test_an_empty_environment_variable_reads_the_keychain(self):
        find_identity, _ = keychain(KEYCHAIN)

        actual = sign_example.choose({"DEBUGDRAWER_SIGN_IDENTITY": ""}, find_identity)

        self.assertEqual(actual, (DEVELOPMENT, None))


class CodesignCommandTests(unittest.TestCase):
    def test_the_command_re_signs_the_bundle_keeping_its_entitlements(self):
        actual = sign_example.codesign_command(DEVELOPMENT, "/tmp/debugdrawer-example/DebugDrawerExample.app")

        self.assertEqual(actual, [
            "codesign", "--force", "--deep", "--timestamp=none",
            "--preserve-metadata=entitlements", "--sign", DEVELOPMENT,
            "/tmp/debugdrawer-example/DebugDrawerExample.app",
        ])


class AppGroupTests(unittest.TestCase):
    def test_the_team_is_read_from_codesigns_display(self):
        output = "Executable=/tmp/App.app/Contents/MacOS/App\nIdentifier=com.example\nTeamIdentifier=9ABCDE1234\nSealed Resources version=2\n"

        actual = sign_example.team_identifier(output)

        self.assertEqual(actual, "9ABCDE1234")

    def test_an_ad_hoc_signature_has_no_team(self):
        output = "Identifier=com.example\nSignature=adhoc\nTeamIdentifier=not set\n"

        actual = sign_example.team_identifier(output)

        self.assertIsNone(actual)

    def test_the_group_is_prefixed_with_the_team_and_the_other_entitlements_kept(self):
        entitlements = {"com.apple.security.get-task-allow": True}

        actual = sign_example.with_app_group(entitlements, "9ABCDE1234", "com.debugdrawer.example")

        self.assertEqual(actual, {
            "com.apple.security.get-task-allow": True,
            "com.apple.security.application-groups": ["9ABCDE1234.com.debugdrawer.example"],
        })

    def test_the_group_replaces_any_group_the_app_was_built_with(self):
        entitlements = {"com.apple.security.application-groups": ["group.com.debugdrawer.example"]}

        actual = sign_example.with_app_group(entitlements, "9ABCDE1234", "com.debugdrawer.example")

        self.assertEqual(actual["com.apple.security.application-groups"], ["9ABCDE1234.com.debugdrawer.example"])

    def test_the_command_signs_the_app_alone_with_the_entitlements(self):
        actual = sign_example.entitlements_command(DEVELOPMENT, "/tmp/App.app", "/tmp/App.entitlements")

        self.assertEqual(actual, [
            "codesign", "--force", "--timestamp=none",
            "--entitlements", "/tmp/App.entitlements", "--sign", DEVELOPMENT, "/tmp/App.app",
        ])


if __name__ == "__main__":
    unittest.main()
