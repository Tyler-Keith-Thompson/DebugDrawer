"""Tests of scripts/modules.py's check that no two snapshot references of one test target share a
base name, which `just modules` (and so `just record-snapshots`) runs over every test target:
rules_xcodeproj copies a target's references into one flat bundle, where two such names collide;
of the tags it gives the generated test targets; and of what SwiftPM skips."""

import importlib.machinery
import importlib.util
import os
import re
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


class PerformanceTestTagTests(unittest.TestCase):
    """A performance target's swift_test runs alone (DD-178): its wall-clock budgets are measured
    after every other action, not beside them."""

    def test_a_performance_target_swift_test_is_exclusive_and_not_debug_only(self):
        name = modules.PERFORMANCE_TESTS[0]
        build = modules.test_build_bazel(name, [])

        actual = re.search(r'swift_test\(\n    name = "%s",\n(.*?)\n\)' % modules.performance_target(name), build, re.S).group(1)

        self.assertIn('    tags = ["exclusive"],', actual)

    def test_a_performance_target_library_is_not_exclusive(self):
        name = modules.PERFORMANCE_TESTS[0]
        build = modules.test_build_bazel(name, [])

        actual = re.search(r'swift_library\(\n    name = "%sLibrary",\n(.*?)\n\)' % modules.performance_target(name), build, re.S).group(1)

        self.assertNotIn("exclusive", actual)

    def test_the_rest_of_a_performance_test_package_runs_in_parallel_and_stays_debug_only(self):
        name = modules.PERFORMANCE_TESTS[0]
        build = modules.test_build_bazel(name, [])

        actual = re.search(r'swift_test\(\n    name = "%s",\n(.*?)\n\)' % name, build, re.S).group(1)

        self.assertIn('    tags = ["debug-only"],', actual)

    def test_a_target_without_performance_tests_has_no_exclusive_test(self):
        name = next(name for name, _ in modules.TEST_TARGETS
                    if name not in modules.PERFORMANCE_TESTS and not modules.simulator_test(name))

        actual = modules.test_build_bazel(name, [])

        self.assertNotIn("exclusive", actual)


class SwiftPMPerformanceSkipTests(unittest.TestCase):
    """SwiftPM builds the performance targets in debug but runs none of them (DD-188): `swift test`
    skips every test whose identifier starts with one's module name."""

    def test_the_skip_pattern_matches_a_swift_testing_test_in_every_performance_target(self):
        pattern = re.compile(modules.swift_test_performance_skip())

        actual = [name for name in modules.PERFORMANCE_TESTS
                  if not pattern.search(modules.performance_target(name) + ".LeakDetectorOverheadTests/overhead()")]

        self.assertEqual([], actual)

    def test_the_skip_pattern_matches_an_xctest_test_in_a_performance_target(self):
        pattern = re.compile(modules.swift_test_performance_skip())
        identifier = modules.performance_target(modules.PERFORMANCE_TESTS[0]) + ".SpeedTests/testSpeed"

        actual = pattern.search(identifier)

        self.assertIsNotNone(actual)

    def test_the_skip_pattern_spares_the_target_a_performance_target_was_split_from(self):
        pattern = re.compile(modules.swift_test_performance_skip())
        identifier = modules.PERFORMANCE_TESTS[0] + ".StoreTests/recordsAnEvent()"

        actual = pattern.search(identifier)

        self.assertIsNone(actual)

    def test_the_skip_pattern_spares_a_suite_named_like_a_performance_target_elsewhere(self):
        pattern = re.compile(modules.swift_test_performance_skip())
        identifier = "DebugDrawerTests." + modules.performance_target(modules.PERFORMANCE_TESTS[0]) + "/runs()"

        actual = pattern.search(identifier)

        self.assertIsNone(actual)


if __name__ == "__main__":
    unittest.main()
