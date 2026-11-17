"""Tests of the release gates' pure parts (scripts/release.py): the next version, the changelog
entry lookup, reading diagnose-api-breaking-changes' summary, and whether a release may be tagged."""

import importlib.machinery
import importlib.util
import os
import unittest

RUNFILES = os.getcwd()
SCRIPT = os.path.join(RUNFILES, "scripts", "release.py")

loader = importlib.machinery.SourceFileLoader("release", SCRIPT)
specification = importlib.util.spec_from_loader("release", loader)
release = importlib.util.module_from_spec(specification)
loader.exec_module(release)


class NextVersionTests(unittest.TestCase):
    def test_a_patch_bump_raises_the_patch(self):
        self.assertEqual(release.next_version("v0.1.1", "patch").tag, "v0.1.2")

    def test_a_minor_bump_raises_the_minor_and_zeroes_the_patch(self):
        self.assertEqual(release.next_version("v0.1.1", "minor").tag, "v0.2.0")

    def test_a_major_bump_zeroes_the_minor_and_the_patch(self):
        self.assertEqual(release.next_version("v0.1.1", "major").tag, "v1.0.0")

    def test_with_no_tag_the_first_release_is_0_0_1(self):
        self.assertEqual(release.next_version("", "minor").tag, "v0.0.1")

    def test_an_unknown_bump_is_refused(self):
        with self.assertRaises(ValueError):
            release.next_version("v0.1.1", "huge")

    def test_a_tag_that_is_not_a_version_is_refused(self):
        with self.assertRaises(ValueError):
            release.next_version("v0.1", "patch")


CHANGELOG = """# Changelog

## [Unreleased]

- Something on main.

## [0.1.2] - 2026-11-17

### Added

- DD-59: a changelog.

## [0.1.1]
## [0.1.0] - 2026-11-16

- DD-28: notifications.
"""


class ChangelogEntryTests(unittest.TestCase):
    def test_the_entry_is_the_text_under_its_heading_up_to_the_next(self):
        expected = "### Added\n\n- DD-59: a changelog."

        actual = release.changelog_entry(CHANGELOG, release.Version.parse("v0.1.2"))

        self.assertEqual(actual, expected)

    def test_the_last_entry_runs_to_the_end_of_the_file(self):
        actual = release.changelog_entry(CHANGELOG, release.Version.parse("0.1.0"))

        self.assertEqual(actual, "- DD-28: notifications.")

    def test_a_version_with_no_heading_has_no_entry(self):
        self.assertIsNone(release.changelog_entry(CHANGELOG, release.Version.parse("0.1.3")))

    def test_a_heading_with_nothing_under_it_is_no_entry(self):
        self.assertIsNone(release.changelog_entry(CHANGELOG, release.Version.parse("0.1.1")))

    def test_the_unreleased_section_is_no_version_entry(self):
        self.assertIsNone(release.changelog_entry("## [Unreleased]\n\n- Work.\n", release.Version.parse("0.1.2")))

    def test_a_version_is_not_matched_by_a_longer_one(self):
        self.assertIsNone(release.changelog_entry("## [0.1.20]\n\n- Work.\n", release.Version.parse("0.1.2")))

    def test_an_empty_changelog_has_no_entry(self):
        self.assertIsNone(release.changelog_entry("", release.Version.parse("0.1.2")))


# Trimmed from a real run against v0.1.1: compiler warnings first, then the summary.
DIAGNOSE_OUTPUT = """Build complete! (31.59 sec)
/repo/Sources/DebugDrawer/DebugDrawerReport.swift:22:14: warning: API breakage: enumelement DebugDrawerReport.Kind.movie has been added as a new enum case [#api-digester-breaking-change]
        case movie
             ^
<unknown>:0: warning: API breakage: constructor AppInfoPlugin.init() has been removed [#api-digester-breaking-change]
1 breaking change detected in DebugDrawer:
  \U0001f494 API breakage: enumelement DebugDrawerReport.Kind.movie has been added as a new enum case
No breaking changes detected in DebugDrawerAccessibilityPlugin
2 breaking changes detected in DebugDrawerAppInfoPlugin:
  \U0001f494 API breakage: constructor AppInfoPlugin.init() has been removed
  \U0001f494 API breakage: func DebugDrawer.installAppInfo() has been renamed to func installAppInfo(buildMetadata:)
No breaking changes detected in DebugDrawerViewInspectorPlugin
Skipping DebugDrawerAnalyticsPlugin because it does not exist in the baseline
"""


class ParseBreakagesTests(unittest.TestCase):
    def test_each_break_in_the_summary_is_read_with_its_module(self):
        expected = [
            release.Breakage("DebugDrawer", "enumelement DebugDrawerReport.Kind.movie has been added as a new enum case"),
            release.Breakage("DebugDrawerAppInfoPlugin", "constructor AppInfoPlugin.init() has been removed"),
            release.Breakage("DebugDrawerAppInfoPlugin",
                             "func DebugDrawer.installAppInfo() has been renamed to func installAppInfo(buildMetadata:)"),
        ]

        actual = release.parse_breakages(DIAGNOSE_OUTPUT)

        self.assertEqual(actual, expected)

    def test_output_with_no_breaks_has_none(self):
        output = "No breaking changes detected in DebugDrawer\nNo breaking changes detected in DebugDrawerConsolePlugin\n"

        self.assertEqual(release.parse_breakages(output), [])

    def test_compiler_warnings_alone_are_not_read_as_breaks(self):
        output = "<unknown>:0: warning: API breakage: constructor AppInfoPlugin.init() has been removed\n"

        self.assertEqual(release.parse_breakages(output), [])


class DecideTests(unittest.TestCase):
    """The decision table: bump kind x breaks found x allow-breaking."""

    BREAK = [release.Breakage("DebugDrawer", "func f() has been removed")]

    def test_the_table(self):
        cases = [
            ("patch", [], False, True),
            ("patch", [], True, True),
            ("patch", self.BREAK, False, False),
            ("patch", self.BREAK, True, True),
            ("minor", [], False, True),
            ("minor", self.BREAK, False, False),
            ("minor", self.BREAK, True, True),
            ("major", [], False, True),
            ("major", self.BREAK, False, True),
            ("major", self.BREAK, True, True),
        ]
        for bump, breakages, allow_breaking, expected in cases:
            with self.subTest(bump=bump, breaks=len(breakages), allow_breaking=allow_breaking):
                actual = release.decide(bump, breakages, allow_breaking)

                self.assertEqual(actual.proceed, expected)

    def test_a_refusal_names_the_override(self):
        actual = release.decide("patch", self.BREAK, False)

        self.assertIn("just deploy patch allow-breaking", actual.reason)


class ReleaseNotesTests(unittest.TestCase):
    def test_notes_without_breaks_are_the_entry(self):
        self.assertEqual(release.release_notes("- DD-59: a changelog.", []), "- DD-59: a changelog.\n")

    def test_notes_list_each_break_after_the_entry(self):
        breakages = [release.Breakage("DebugDrawerFileBrowserPlugin", "func DebugDrawer.installFileBrowser() has been removed")]
        expected = ("- DD-48: the File Browser.\n\n### API breaks\n\n"
                    "- `DebugDrawerFileBrowserPlugin`: func DebugDrawer.installFileBrowser() has been removed\n")

        actual = release.release_notes("- DD-48: the File Browser.", breakages)

        self.assertEqual(actual, expected)


if __name__ == "__main__":
    unittest.main()
