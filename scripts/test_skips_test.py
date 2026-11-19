"""Tests of scripts/test_skips.py, which turns SKIP_TESTS into what each SwiftPM test runner takes:
`--skip` regular expressions for swift test (`just spm-test-mac`) and `-skip-testing:` for
xcodebuild (`just spm-platform-test`, `just spm-catalyst-test`, `just test-ios`)."""

import contextlib
import importlib.machinery
import importlib.util
import io
import os
import re
import unittest

RUNFILES = os.getcwd()
SCRIPT = os.path.join(RUNFILES, "scripts", "test_skips.py")

loader = importlib.machinery.SourceFileLoader("test_skips", SCRIPT)
specification = importlib.util.spec_from_loader("test_skips", loader)
test_skips = importlib.util.module_from_spec(specification)
loader.exec_module(test_skips)

KNOWN = {"ATests", "BTests"}


def skipped(entry, identifier):
    """Whether swift test's `--skip` pattern for `entry` matches SwiftPM's `identifier`."""
    return re.search(test_skips.swift_test_pattern(entry), identifier) is not None


class EntriesTests(unittest.TestCase):
    def test_entries_split_at_commas_and_whitespace(self):
        expected = ["ATests/Suite/test()", "BTests", "ATests/Other"]

        actual = test_skips.entries(" ATests/Suite/test(), BTests\nATests/Other ,", KNOWN)

        self.assertEqual(actual, expected)

    def test_no_value_skips_nothing(self):
        self.assertEqual(test_skips.entries("", KNOWN), [])
        self.assertEqual(test_skips.entries(None, KNOWN), [])

    def test_an_unknown_target_is_an_error_naming_it(self):
        with self.assertRaisesRegex(ValueError, "CTests"):
            test_skips.entries("ATests/Suite,CTests/Suite/test()", KNOWN)

    def test_a_bare_test_name_is_an_unknown_target(self):
        with self.assertRaisesRegex(ValueError, "storeShowsConnection"):
            test_skips.entries("storeShowsConnection", KNOWN)

    def test_the_repository_knows_its_test_and_performance_targets(self):
        modules = test_skips._modules()

        actual = test_skips.test_targets(modules)

        self.assertIn("DebugDrawerTests", actual)
        self.assertIn(modules.performance_targets()[0], actual)


class SwiftTestPatternTests(unittest.TestCase):
    def test_a_test_skips_itself_only(self):
        entry = "ATests/Suite/test()"

        self.assertTrue(skipped(entry, "ATests.Suite/test()"))
        self.assertFalse(skipped(entry, "ATests.Suite/testMore()"))
        self.assertFalse(skipped(entry, "ATests.Suite/other()"))

    def test_a_parameterized_test_skips_its_cases(self):
        entry = "ATests/Suite/noUnit(value:)"

        self.assertTrue(skipped(entry, "ATests.Suite/noUnit(value:)"))
        self.assertTrue(skipped(entry, "ATests.Suite/noUnit(value:)/0"))

    def test_a_suite_skips_its_tests_and_not_a_suite_it_prefixes(self):
        entry = "ATests/Suite"

        self.assertTrue(skipped(entry, "ATests.Suite/test()"))
        self.assertTrue(skipped(entry, "ATests.Suite/Inner/test()"))
        self.assertFalse(skipped(entry, "ATests.SuiteTwo/test()"))

    def test_a_target_skips_its_tests_and_not_another_targets(self):
        entry = "ATests"

        self.assertTrue(skipped(entry, "ATests.Suite/test()"))
        self.assertFalse(skipped(entry, "ATestsMore.Suite/test()"))
        self.assertFalse(skipped(entry, "BTests.ATests/test()"))

    def test_an_xctest_method_skips_itself(self):
        entry = "ATests/Case/testThing"

        self.assertTrue(skipped(entry, "ATests.Case/testThing"))
        self.assertFalse(skipped(entry, "ATests.Case/testThingMore"))

    def test_the_same_name_in_another_target_runs(self):
        self.assertFalse(skipped("ATests/Suite/test()", "BTests.Suite/test()"))

    def test_each_entry_is_a_skip_argument_of_its_own(self):
        expected = ["--skip", r"^ATests\.Suite/test\(\)(/|$)", "--skip", r"^BTests\."]

        actual = test_skips.swift_test_arguments(["ATests/Suite/test()", "BTests"])

        self.assertEqual(actual, expected)


class XcodebuildArgumentsTests(unittest.TestCase):
    def test_each_entry_is_skip_testing_as_written(self):
        expected = ["-skip-testing:ATests/Suite/test()", "-skip-testing:BTests"]

        actual = test_skips.xcodebuild_arguments(["ATests/Suite/test()", "BTests"])

        self.assertEqual(actual, expected)

    def test_a_target_keeps_only_its_own_entries(self):
        expected = ["-skip-testing:BTests/Suite"]

        actual = test_skips.xcodebuild_arguments(["ATests/Suite/test()", "BTests/Suite"], "BTests")

        self.assertEqual(actual, expected)


class MainTests(unittest.TestCase):
    def run_main(self, argv, value):
        output = io.StringIO()
        errors = io.StringIO()
        with contextlib.redirect_stdout(output), contextlib.redirect_stderr(errors):
            status = test_skips.main(argv, {"SKIP_TESTS": value})
        return status, output.getvalue(), errors.getvalue()

    def test_xcodebuild_prints_one_argument_a_line(self):
        expected = "-skip-testing:DebugDrawerTests/CaptureBufferTests/countBound()\n"

        actual = self.run_main(["xcodebuild"], "DebugDrawerTests/CaptureBufferTests/countBound()")

        self.assertEqual(actual, (0, expected, ""))

    def test_nothing_to_skip_prints_nothing(self):
        actual = self.run_main(["swift-test"], "")

        self.assertEqual(actual, (0, "", ""))

    def test_an_unknown_target_fails_with_a_message(self):
        status, output, errors = self.run_main(["swift-test"], "Nope/Suite")

        self.assertEqual(status, 1)
        self.assertEqual(output, "")
        self.assertIn("Nope", errors)


if __name__ == "__main__":
    unittest.main()
