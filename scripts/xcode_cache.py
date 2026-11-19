#!/usr/bin/env python3
"""Build settings that let xcodebuild reuse compile results from any checkout of the repository.

Usage:
    python3 scripts/xcode_cache.py DERIVED_DATA [--tests]   # one KEY=VALUE setting a line

Each worktree has a `.build` of its own, so without these a fresh worktree's xcodebuild stages
(`just test-ios`, `just spm-platform`, `just spm-platform-test`, `just spm-catalyst`,
`just spm-catalyst-test`) compile everything again. With them, Xcode's compilation caching keeps
each compile's outputs in one content-addressed store shared by every checkout (CAS, under
~/Library/Caches), keyed by the compile's inputs rather than by where they sit, and a compile whose
inputs another checkout already built replays from it. The store takes concurrent builds from many
processes, as every Xcode on a Mac shares DerivedData's own, and prunes itself to Xcode's default
size limit.

For a key to match across checkouts, nothing in it may name the checkout:
- The paths are prefix-mapped (SWIFT_/CLANG_OTHER_PREFIX_MAPPINGS): the derived data to /^derived,
  `Sources` and `.swiftpm` (the compiler's working directory) to /^src, as given, as resolved and
  as Xcode spells it (/tmp for /private/tmp), since the compiler sees one and xcodebuild another.
- The package name is fixed (SWIFT_PACKAGE_NAME). SwiftPM names the root package after its
  directory, the worktree's name, and passes it to every compile as `-package-name`.

`Tests` is mapped only with `--tests`. A mapped file's `#filePath` is the mapped path
(`/^src/Tests/...`), and SnapshotTesting finds each reference beside its test through `#filePath`,
so `just test-ios`, which runs the snapshot tests, leaves `Tests` unmapped: its test targets
compile in each checkout and only the libraries replay. The other test stages run no snapshot test
(SnapshotTesting doesn't build for Mac Catalyst or visionOS), so they map `Tests` as well; a
failing expectation there reports its file as `/^src/Tests/...`. No library reads `#filePath`.

COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS records each compile's "Cache hit" or "Cache miss" in
the build's log (DERIVED_DATA/Logs/Build/*.xcactivitylog), which shows what replayed.
"""

import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CAS = os.path.join(os.path.expanduser("~"), "Library", "Caches", "debugdrawer-xcode-cas")
# The root package's name in every checkout: its Package.swift `name`, as SwiftPM would derive it
# from a checkout called DebugDrawer.
PACKAGE_NAME = "debugdrawer"
# Directories macOS reaches through /private, which Xcode writes without it.
PRIVATE_LINKS = ("/private/tmp/", "/private/var/", "/private/etc/")


def spellings(path):
    """`path` as given, resolved, and as Xcode writes it, each once."""
    resolved = os.path.realpath(path)
    forms = [path, resolved]
    if resolved.startswith(PRIVATE_LINKS):
        forms.append(resolved[len("/private"):])
    return list(dict.fromkeys(forms))


def prefix_mappings(root, derived_data, tests):
    """The `path=replacement` pairs that keep the checkout's location out of every cache key."""
    mapped = [(derived_data, "/^derived"), (os.path.join(root, "Sources"), "/^src/Sources"),
              (os.path.join(root, ".swiftpm"), "/^src/.swiftpm")]
    if tests:
        mapped.append((os.path.join(root, "Tests"), "/^src/Tests"))
    return [f"{form}={replacement}" for path, replacement in mapped for form in spellings(path)]


def settings(root, derived_data, tests, cas=CAS):
    """The xcodebuild build settings, as KEY=VALUE arguments."""
    mappings = " ".join(prefix_mappings(root, derived_data, tests))
    return [
        "COMPILATION_CACHE_ENABLE_CACHING=YES",
        f"COMPILATION_CACHE_CAS_PATH={cas}",
        "COMPILATION_CACHE_ENABLE_DIAGNOSTIC_REMARKS=YES",
        "SWIFT_ENABLE_PREFIX_MAPPING=YES",
        "CLANG_ENABLE_PREFIX_MAPPING=YES",
        f"SWIFT_OTHER_PREFIX_MAPPINGS={mappings}",
        f"CLANG_OTHER_PREFIX_MAPPINGS={mappings}",
        f"SWIFT_PACKAGE_NAME={PACKAGE_NAME}",
    ]


def main(argv):
    arguments = [argument for argument in argv if argument != "--tests"]
    if len(arguments) != 1:
        raise SystemExit(__doc__)
    derived_data = os.path.abspath(arguments[0])
    if any(" " in path for path in (ROOT, derived_data)):
        raise SystemExit(f"xcode_cache.py: a prefix mapping can't hold a space: {ROOT}, {derived_data}")
    print("\n".join(settings(ROOT, derived_data, "--tests" in argv)))


if __name__ == "__main__":
    main(sys.argv[1:])
