"""Tests of scripts/xcode_cache.py, the build settings with which the xcodebuild recipes share
compile results between checkouts: no setting names the checkout except through a prefix mapping,
and `Tests` is mapped only when asked, so `just test-ios`'s snapshot tests keep their #filePath."""

import importlib.machinery
import importlib.util
import os
import tempfile
import unittest

RUNFILES = os.getcwd()
SCRIPT = os.path.join(RUNFILES, "scripts", "xcode_cache.py")

loader = importlib.machinery.SourceFileLoader("xcode_cache", SCRIPT)
specification = importlib.util.spec_from_loader("xcode_cache", loader)
xcode_cache = importlib.util.module_from_spec(specification)
loader.exec_module(xcode_cache)


def setting(settings, key):
    values = [line.split("=", 1)[1] for line in settings if line.split("=", 1)[0] == key]
    assert len(values) == 1, f"{key} appears {len(values)} times"
    return values[0]


class SpellingsTests(unittest.TestCase):
    def test_a_resolved_path_is_spelled_once(self):
        with tempfile.TemporaryDirectory() as directory:
            resolved = os.path.realpath(directory)

            actual = [form for form in xcode_cache.spellings(resolved) if form == resolved]

        self.assertEqual(actual, [resolved])

    def test_a_path_under_private_tmp_is_also_spelled_as_xcode_writes_it(self):
        path = "/private/tmp/checkout"

        actual = xcode_cache.spellings(path)

        self.assertIn("/tmp/checkout", actual)
        self.assertIn(path, actual)

    def test_a_link_is_spelled_as_given_and_resolved(self):
        with tempfile.TemporaryDirectory() as directory:
            target = os.path.join(directory, "target")
            os.mkdir(target)
            link = os.path.join(directory, "link")
            os.symlink(target, link)

            actual = xcode_cache.spellings(link)

            self.assertIn(link, actual)
            self.assertIn(os.path.realpath(target), actual)


class PrefixMappingsTests(unittest.TestCase):
    def test_sources_the_working_directory_and_the_derived_data_are_mapped(self):
        expected = {"/w/Sources=/^src/Sources", "/w/.swiftpm=/^src/.swiftpm", "/w/.build/xcode-ios=/^derived"}

        actual = set(xcode_cache.prefix_mappings("/w", "/w/.build/xcode-ios", tests=False))

        self.assertEqual(actual, expected)

    def test_tests_are_mapped_only_when_asked(self):
        without = xcode_cache.prefix_mappings("/w", "/w/.build/x", tests=False)
        with_tests = xcode_cache.prefix_mappings("/w", "/w/.build/x", tests=True)

        self.assertNotIn("/w/Tests=/^src/Tests", without)
        self.assertIn("/w/Tests=/^src/Tests", with_tests)

    def test_two_checkouts_map_to_the_same_paths(self):
        first = [mapping.split("=", 1)[1] for mapping in xcode_cache.prefix_mappings("/a/one", "/a/one/.build/x", True)]
        second = [mapping.split("=", 1)[1] for mapping in xcode_cache.prefix_mappings("/b/two", "/b/two/.build/x", True)]

        self.assertEqual(first, second)


class SettingsTests(unittest.TestCase):
    def test_caching_is_on_in_the_shared_store(self):
        actual = xcode_cache.settings("/w", "/w/.build/x", tests=False, cas="/cas")

        self.assertEqual(setting(actual, "COMPILATION_CACHE_ENABLE_CACHING"), "YES")
        self.assertEqual(setting(actual, "COMPILATION_CACHE_CAS_PATH"), "/cas")

    def test_the_default_store_is_in_the_users_caches(self):
        expected = os.path.join(os.path.expanduser("~"), "Library", "Caches", "debugdrawer-xcode-cas")

        actual = setting(xcode_cache.settings("/w", "/w/.build/x", tests=False), "COMPILATION_CACHE_CAS_PATH")

        self.assertEqual(actual, expected)

    def test_swift_and_clang_get_the_same_mappings(self):
        actual = xcode_cache.settings("/w", "/w/.build/x", tests=True)

        self.assertEqual(setting(actual, "SWIFT_OTHER_PREFIX_MAPPINGS"), setting(actual, "CLANG_OTHER_PREFIX_MAPPINGS"))
        self.assertEqual(setting(actual, "SWIFT_ENABLE_PREFIX_MAPPING"), "YES")
        self.assertEqual(setting(actual, "CLANG_ENABLE_PREFIX_MAPPING"), "YES")

    def test_the_package_name_is_the_same_in_every_checkout(self):
        first = setting(xcode_cache.settings("/a/agent-1", "/a/agent-1/.build/x", tests=False), "SWIFT_PACKAGE_NAME")
        second = setting(xcode_cache.settings("/b/agent-2", "/b/agent-2/.build/x", tests=False), "SWIFT_PACKAGE_NAME")

        self.assertEqual(first, "debugdrawer")
        self.assertEqual(second, first)

    def test_the_checkout_appears_only_in_the_mappings(self):
        actual = xcode_cache.settings("/a/agent-1", "/a/agent-1/.build/x", tests=True, cas="/cas")

        unmapped = [line for line in actual if "agent-1" in line and "PREFIX_MAPPINGS" not in line]

        self.assertEqual(unmapped, [])

    def test_the_project_wide_mapping_stays_off(self):
        # It maps the whole checkout, Tests included, which would move the snapshot tests' #filePath.
        actual = xcode_cache.settings("/w", "/w/.build/x", tests=False)

        self.assertFalse(any(line.startswith(("SWIFT_ENABLE_PROJECT_PREFIX_MAPPING", "CLANG_ENABLE_PROJECT_PREFIX_MAPPING")) for line in actual))


if __name__ == "__main__":
    unittest.main()
