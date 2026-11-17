"""Tests of the release API check's pure parts (scripts/release_api.py): what a symbol graph's
public surface is, and what a release build lacks that the debug build has."""

import importlib.machinery
import importlib.util
import os
import unittest

RUNFILES = os.getcwd()
SCRIPT = os.path.join(RUNFILES, "scripts", "release_api.py")

loader = importlib.machinery.SourceFileLoader("release_api", SCRIPT)
specification = importlib.util.spec_from_loader("release_api", loader)
release_api = importlib.util.module_from_spec(specification)
loader.exec_module(release_api)


def symbol(usr, path, kind="swift.struct", display="Structure"):
    return {
        "identifier": {"precise": usr},
        "pathComponents": path.split("."),
        "kind": {"identifier": kind, "displayName": display},
    }


def graph(symbols=(), relationships=()):
    return {"symbols": list(symbols), "relationships": list(relationships)}


PLUGIN = symbol("s:P", "NetworkPlugin")
BODY = symbol("s:P4body", "NetworkPlugin.body", "swift.property", "Instance Property")
STORE = symbol("s:S", "NetworkStore", "swift.class", "Class")
CONFORMANCE = {"source": "s:S", "kind": "conformsTo", "target": "s:7Combine16ObservableObjectP",
               "targetFallback": "Combine.ObservableObject"}


class SurfaceTests(unittest.TestCase):
    def test_a_symbol_is_keyed_by_its_usr_and_printed_with_its_kind_and_path(self):
        actual = release_api.surface(graph([BODY]))

        self.assertEqual(actual, {"s:P4body": "Instance Property NetworkPlugin.body"})

    def test_a_conformance_to_another_module_prints_the_target_fallback(self):
        actual = release_api.surface(graph([STORE], [CONFORMANCE]))

        self.assertEqual(actual["s:S conformsTo s:7Combine16ObservableObjectP"],
                         "NetworkStore conformsTo Combine.ObservableObject")

    def test_members_a_protocol_extension_supplies_are_left_to_the_conformance(self):
        synthesized = symbol("s:7SwiftUI4ViewPAAE7opacity::SYNTHESIZED::s:P", "NetworkPlugin.opacity(_:)")

        actual = release_api.surface(graph([synthesized]))

        self.assertEqual(actual, {})

    def test_extension_blocks_are_left_to_their_members(self):
        block = symbol("s:e:s:P", "NetworkPlugin", "swift.extension", "Extension")

        actual = release_api.surface(graph([block]))

        self.assertEqual(actual, {})

    def test_member_of_relationships_are_not_part_of_the_surface(self):
        member = {"source": "s:P4body", "kind": "memberOf", "target": "s:P"}

        actual = release_api.surface(graph([PLUGIN, BODY], [member]))

        self.assertEqual(sorted(actual), ["s:P", "s:P4body"])


class MissingInReleaseTests(unittest.TestCase):
    def test_identical_graphs_miss_nothing(self):
        debug = {"Network": [graph([PLUGIN, BODY])]}

        actual = release_api.missing_in_release(debug, debug)

        self.assertEqual(actual, {})

    def test_a_symbol_only_debug_declares_is_missing(self):
        debug = {"Network": [graph([PLUGIN, BODY])]}
        release = {"Network": [graph([PLUGIN])]}

        actual = release_api.missing_in_release(debug, release)

        self.assertEqual(actual, {"Network": ["Instance Property NetworkPlugin.body"]})

    def test_a_conformance_only_debug_declares_is_missing(self):
        debug = {"Network": [graph([STORE], [CONFORMANCE])]}
        release = {"Network": [graph([STORE])]}

        actual = release_api.missing_in_release(debug, release)

        self.assertEqual(actual, {"Network": ["NetworkStore conformsTo Combine.ObservableObject"]})

    def test_a_module_release_has_no_graph_for_is_missing_whole(self):
        debug = {"Network": [graph([PLUGIN, BODY])]}

        actual = release_api.missing_in_release(debug, {})

        self.assertEqual(actual, {"Network": ["Instance Property NetworkPlugin.body", "Structure NetworkPlugin"]})

    def test_symbols_only_release_declares_are_not_reported(self):
        debug = {"Network": [graph([PLUGIN])]}
        release = {"Network": [graph([PLUGIN, BODY])]}

        actual = release_api.missing_in_release(debug, release)

        self.assertEqual(actual, {})

    def test_a_symbol_in_an_extension_graph_counts_for_its_module(self):
        install = symbol("s:D7installNetwork", "DebugDrawer.installNetwork()", "swift.method", "Instance Method")
        debug = {"Network": [graph([PLUGIN]), graph([install])]}
        release = {"Network": [graph([PLUGIN]), graph([install])]}

        actual = release_api.missing_in_release(debug, release)

        self.assertEqual(actual, {})

    def test_a_signature_change_is_missing_since_the_usr_spells_the_type(self):
        debug = {"Network": [graph([symbol("s:P4initSi", "NetworkPlugin.init(_:)", "swift.init", "Initializer")])]}
        release = {"Network": [graph([symbol("s:P4initSS", "NetworkPlugin.init(_:)", "swift.init", "Initializer")])]}

        actual = release_api.missing_in_release(debug, release)

        self.assertEqual(actual, {"Network": ["Initializer NetworkPlugin.init(_:)"]})


class ReportTests(unittest.TestCase):
    def test_nothing_missing_passes(self):
        self.assertEqual(release_api.report({}), 0)

    def test_anything_missing_fails(self):
        self.assertEqual(release_api.report({"Network": ["Structure NetworkPlugin"]}), 1)


if __name__ == "__main__":
    unittest.main()
