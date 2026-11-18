"""Tests of scripts/modules.py's check that no two snapshot references of one test target share a
base name, which `just modules` (and so `just record-snapshots`) runs over every test target:
rules_xcodeproj copies a target's references into one flat bundle, where two such names collide."""

import importlib.machinery
import importlib.util
import os
import tempfile
import unittest

RUNFILES = os.getcwd()
SCRIPT = os.path.join(RUNFILES, "scripts", "modules.py")

loader = importlib.machinery.SourceFileLoader("modules", SCRIPT)
specification = importlib.util.spec_from_loader("modules", loader)
modules = importlib.util.module_from_spec(specification)
loader.exec_module(modules)


class SnapshotNameClashTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = self.directory.name

    def tearDown(self):
        self.directory.cleanup()

    def write(self, path):
        path = os.path.join(self.root, path)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as file:
            file.write(b"")

    def test_a_target_without_snapshots_has_no_clash(self):
        os.makedirs(os.path.join(self.root, "Tests", "ATests"))

        actual = modules.snapshot_name_clashes(self.root, "ATests")

        self.assertEqual(actual, [])

    def test_unique_names_across_suites_have_no_clash(self):
        self.write("Tests/ATests/__Snapshots__/MockSnapshotTests/mockEditor-colorScheme.light.png")
        self.write("Tests/ATests/__Snapshots__/ConditionSnapshotTests/conditionEditor-colorScheme.light.png")

        actual = modules.snapshot_name_clashes(self.root, "ATests")

        self.assertEqual(actual, [])

    def test_two_suites_holding_the_same_name_clash_naming_both_paths(self):
        self.write("Tests/ATests/__Snapshots__/MockSnapshotTests/editor-colorScheme.light.png")
        self.write("Tests/ATests/__Snapshots__/ConditionSnapshotTests/editor-colorScheme.light.png")
        self.write("Tests/ATests/__Snapshots__/ConditionSnapshotTests/row-colorScheme.light.png")
        expected = [[
            "Tests/ATests/__Snapshots__/ConditionSnapshotTests/editor-colorScheme.light.png",
            "Tests/ATests/__Snapshots__/MockSnapshotTests/editor-colorScheme.light.png",
        ]]

        actual = modules.snapshot_name_clashes(self.root, "ATests")

        self.assertEqual(actual, expected)

    def test_every_path_sharing_a_name_is_named_and_each_name_is_reported_once_in_order(self):
        self.write("Tests/ATests/__Snapshots__/A/section.png")
        self.write("Tests/ATests/__Snapshots__/B/section.png")
        self.write("Tests/ATests/__Snapshots__/C/section.png")
        self.write("Tests/ATests/__Snapshots__/A/editor.png")
        self.write("Tests/ATests/__Snapshots__/B/editor.png")
        expected = [
            ["Tests/ATests/__Snapshots__/A/editor.png", "Tests/ATests/__Snapshots__/B/editor.png"],
            [
                "Tests/ATests/__Snapshots__/A/section.png",
                "Tests/ATests/__Snapshots__/B/section.png",
                "Tests/ATests/__Snapshots__/C/section.png",
            ],
        ]

        actual = modules.snapshot_name_clashes(self.root, "ATests")

        self.assertEqual(actual, expected)

    def test_the_same_name_in_two_test_targets_is_no_clash(self):
        self.write("Tests/ATests/__Snapshots__/Suite/editor.png")
        self.write("Tests/BTests/__Snapshots__/Suite/editor.png")

        actual = modules.snapshot_name_clashes(self.root, "ATests") + modules.snapshot_name_clashes(self.root, "BTests")

        self.assertEqual(actual, [])


if __name__ == "__main__":
    unittest.main()
