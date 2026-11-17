"""Pins what tools/documentation_coverage.py counts as documented, on hand-written symbol graphs."""

import json
import os
import subprocess
import sys
import tempfile
import unittest

SCRIPT = os.path.join(os.getcwd(), "tools", "documentation_coverage.py")


def symbol(path, kind="swift.struct", precise="s:4Test", doc=None):
    value = {
        "kind": {"identifier": kind, "displayName": "Structure"},
        "identifier": {"precise": precise},
        "pathComponents": path,
    }
    if doc is not None:
        value["docComment"] = {"lines": [{"text": line} for line in doc]}
    return value


def run(symbols):
    """Runs the check over one symbol graph of `symbols`; returns (status, output, stamp written)."""
    with tempfile.TemporaryDirectory() as directory:
        with open(os.path.join(directory, "Test.symbols.json"), "w") as f:
            json.dump({"symbols": symbols}, f)
        stamp = os.path.join(directory, "stamp")
        result = subprocess.run(
            [sys.executable, "-I", SCRIPT, directory, stamp], capture_output=True, text=True, check=False
        )
        return result.returncode, result.stdout, os.path.exists(stamp)


class DocumentationCoverageTests(unittest.TestCase):
    def test_a_documented_symbol_passes_and_writes_the_stamp(self):
        actual = run([symbol(["Greeting"], doc=["A greeting."])])

        self.assertEqual(actual, (0, "", True))

    def test_a_symbol_with_no_doc_comment_fails_and_is_named(self):
        status, output, stamped = run([symbol(["Greeting"], doc=["A greeting."]), symbol(["Greeting", "name"])])

        self.assertEqual((status, stamped), (1, False))
        self.assertIn("Structure Greeting.name", output)

    def test_a_doc_comment_of_blank_lines_counts_as_none(self):
        status, _, _ = run([symbol(["Greeting"], doc=["", "  "])])

        self.assertEqual(status, 1)

    def test_extension_blocks_and_synthesized_members_are_skipped(self):
        symbols = [
            symbol(["View"], kind="swift.extension"),
            symbol(["Greeting", "id"], precise="s:4Test::SYNTHESIZED::s:4Greeting"),
        ]

        actual = run(symbols)

        self.assertEqual(actual, (0, "", True))

    def test_an_empty_directory_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            result = subprocess.run(
                [sys.executable, "-I", SCRIPT, directory, os.path.join(directory, "stamp")],
                capture_output=True,
                text=True,
                check=False,
            )

        self.assertEqual(result.returncode, 1)


if __name__ == "__main__":
    unittest.main()
