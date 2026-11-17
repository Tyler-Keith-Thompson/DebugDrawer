"""Checks that each precompiled shader (tools/metallibs.py) was compiled from its Metal source as it
is now, without needing the Metal toolchain: each generated file records its source's SHA-256."""

import glob
import hashlib
import os
import re
import unittest

RUNFILES = os.getcwd()


class MetallibTests(unittest.TestCase):
    def test_each_generated_library_matches_its_source(self):
        sources = sorted(glob.glob(os.path.join(RUNFILES, "Sources", "*", "Shaders", "*.metal")))
        self.assertTrue(sources, "no Metal sources in the test's data")
        for source in sources:
            module = os.path.dirname(os.path.dirname(source))
            name = os.path.splitext(os.path.basename(source))[0]
            with open(source, "rb") as f:
                expected = hashlib.sha256(f.read()).hexdigest()
            generated = sorted(glob.glob(os.path.join(module, f"{name}Shader+*Library.swift")))
            self.assertTrue(generated, f"{source} has no generated library: run `just metallibs`")
            for path in generated:
                with open(path) as f:
                    match = re.search(r"^// Source SHA-256: ([0-9a-f]{64})$", f.read(), re.MULTILINE)
                self.assertIsNotNone(match, f"{path} records no source hash")
                self.assertEqual(match.group(1), expected, f"{path} is older than {source}: run `just metallibs`")


if __name__ == "__main__":
    unittest.main()
