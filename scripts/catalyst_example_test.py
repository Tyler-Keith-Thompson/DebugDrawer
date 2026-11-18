"""Tests of how scripts/catalyst_example.py derives the Catalyst example's package from the example's
sources: every Example/iOS file, a target per example library imported (followed through the
libraries' own imports), a product per DebugDrawer import, and CATALYST_EXAMPLE_EXCLUDE's files
left out, so the build of a package missing one fails."""

import importlib.machinery
import importlib.util
import os
import tempfile
import unittest

RUNFILES = os.getcwd()
SCRIPT = os.path.join(RUNFILES, "scripts", "catalyst_example.py")

loader = importlib.machinery.SourceFileLoader("catalyst_example", SCRIPT)
specification = importlib.util.spec_from_loader("catalyst_example", loader)
catalyst_example = importlib.util.module_from_spec(specification)
loader.exec_module(catalyst_example)

PACKAGE = """let products: [Product] = [
    .library(name: "DebugDrawer", targets: ["DebugDrawer"]),
    .library(name: "DebugDrawerConsolePlugin", targets: ["DebugDrawerConsolePlugin"]),
    .library(name: "DebugDrawerLeakDetectorPlugin", targets: ["DebugDrawerLeakDetectorPlugin"]),
    .library(name: "DebugDrawerDiskIOInterposer", type: .dynamic, targets: ["DebugDrawerDiskIOInterposer"]),
]
"""


class PlanTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.root = self.directory.name
        self.write("Package.swift", PACKAGE)
        self.write("Example/iOS/App.swift", "import SwiftUI\nimport DebugDrawer\nimport ExampleTestBench\n")
        self.write("Example/iOS/Console.swift", "#if DEBUG\n    import DebugDrawerConsolePlugin\n#endif\n")
        self.write("Example/iOS/Info.plist", "")
        self.write("Example/TestBench/TestBench.swift", "@preconcurrency import DebugDrawerLeakDetectorPlugin\nimport ExampleShared\n")
        self.write("Example/Shared/Shared.swift", "import Foundation\n")

    def tearDown(self):
        self.directory.cleanup()

    def write(self, path, text):
        path = os.path.join(self.root, path)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "w", encoding="utf-8") as file:
            file.write(text)

    def targets(self, exclude=()):
        return {target.name: target for target in catalyst_example.plan(self.root, exclude)}

    def test_the_app_compiles_every_swift_file_of_example_ios(self):
        app = self.targets()["ExampleApp_iOS"]
        self.assertEqual(app.sources, ["Example/iOS/App.swift", "Example/iOS/Console.swift"])

    def test_each_debugdrawer_import_is_a_product_and_the_interposer_is_linked(self):
        app = self.targets()["ExampleApp_iOS"]
        self.assertEqual(app.products, ["DebugDrawer", "DebugDrawerConsolePlugin", "DebugDrawerDiskIOInterposer"])

    def test_an_example_library_import_is_a_target_of_its_directory_and_its_imports_are_followed(self):
        targets = self.targets()
        self.assertEqual(targets["ExampleApp_iOS"].libraries, ["ExampleTestBench"])
        bench = targets["ExampleTestBench"]
        self.assertEqual(bench.sources, ["Example/TestBench/TestBench.swift"])
        self.assertEqual(bench.products, ["DebugDrawerLeakDetectorPlugin"])
        self.assertEqual(bench.libraries, ["ExampleShared"])
        self.assertEqual(targets["ExampleShared"].sources, ["Example/Shared/Shared.swift"])

    def test_the_package_declares_every_target_with_its_dependencies(self):
        text = catalyst_example.package_swift(self.root, catalyst_example.plan(self.root))
        self.assertIn('.executableTarget(name: "ExampleApp_iOS", dependencies: [\n            "ExampleTestBench",', text)
        self.assertIn('.target(name: "ExampleTestBench", dependencies: [\n            "ExampleShared",', text)
        self.assertIn('.product(name: "DebugDrawerConsolePlugin", package: "DebugDrawer")', text)

    def test_an_excluded_file_is_left_out(self):
        app = self.targets(["Example/iOS/Console.swift"])["ExampleApp_iOS"]
        self.assertEqual(app.sources, ["Example/iOS/App.swift"])
        self.assertNotIn("DebugDrawerConsolePlugin", app.products)

    def test_generate_links_each_source_into_its_target(self):
        work = os.path.join(self.root, "work")
        os.makedirs(work)
        catalyst_example.generate(self.root, work)
        self.assertEqual(sorted(os.listdir(os.path.join(work, "Sources", "ExampleApp_iOS"))), ["App.swift", "Console.swift"])
        self.assertTrue(os.path.islink(os.path.join(work, "Sources", "ExampleTestBench", "TestBench.swift")))
        self.assertTrue(os.path.isfile(os.path.join(work, "Package.swift")))

    def test_an_unknown_debugdrawer_import_is_refused(self):
        self.write("Example/iOS/Missing.swift", "import DebugDrawerNoSuchPlugin\n")
        with self.assertRaises(SystemExit):
            self.targets()

    def test_an_example_library_with_no_directory_is_refused(self):
        self.write("Example/iOS/Missing.swift", "import ExampleNoSuchLibrary\n")
        with self.assertRaises(SystemExit):
            self.targets()


if __name__ == "__main__":
    unittest.main()
