#!/usr/bin/env python3
"""The tests SKIP_TESTS names, in the form each SwiftPM test runner takes.

`SKIP_TESTS="DebugDrawerTests/CaptureBufferTests/countBound(),DebugDrawerNetworkPluginTests/NetworkWebSocketExitTests"`
leaves those tests out of every stage of `just spm-test` (swift test on the Mac, then xcodebuild for
visionOS and Mac Catalyst) and of `just test-ios`. Entries are separated by commas or whitespace,
each written the way xcodebuild's -skip-testing takes it: a test target, `Target/Suite` or
`Target/Suite/test()`. A Swift Testing function keeps its parentheses and argument labels
(`noUnit(value:)`): xcodebuild matches the whole name, and without them skips nothing. An XCTest
method has none (`Target/Class/testName`). `swift test --skip` takes a regular expression over
`Module.Suite/test()` instead, so this writes one anchored on the entry: the same tests, and no
test that merely shares a name in another target.

An entry whose target isn't a test target in scripts/modules.py is an error rather than a skip that
silently matches nothing, as a misspelled -skip-testing does.

    test_skips.py swift-test            `--skip <regex>` for each entry, one word a line
    test_skips.py xcodebuild [TARGET]   `-skip-testing:<entry>` for each entry, only TARGET's if given
"""

import importlib.machinery
import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))


def _modules():
    loader = importlib.machinery.SourceFileLoader("modules", os.path.join(HERE, "modules.py"))
    specification = importlib.util.spec_from_loader("modules", loader)
    module = importlib.util.module_from_spec(specification)
    loader.exec_module(module)
    return module


def test_targets(modules):
    """Every SwiftPM test target: TEST_TARGETS and the performance targets split from them."""
    names = [name for name, _ in modules.TEST_TARGETS]
    return set(names) | set(modules.performance_targets())


def entries(value, known):
    """The entries of a SKIP_TESTS value, split at commas and whitespace, each checked against the
    test targets in `known`."""
    result = [entry.strip("/") for entry in re.split(r"[,\s]+", value or "") if entry.strip("/")]
    unknown = sorted({entry.split("/")[0] for entry in result} - set(known))
    if unknown:
        raise ValueError(
            "SKIP_TESTS names no test target " + ", ".join(unknown)
            + "; write each entry as Target, Target/Suite or Target/Suite/test() (xcodebuild's -skip-testing form)"
        )
    return result


def swift_test_pattern(entry):
    """The `swift test --skip` pattern matching exactly the tests `entry` names. SwiftPM writes a
    test's identifier as `Module.Suite/test()` (`Module.Class/testName` for XCTest), so the target is
    followed by a dot and the rest is kept. A whole target or suite matches what's under it; a test
    matches itself, and a Swift Testing test's arguments too (`test(value:)`)."""
    target, _, rest = entry.partition("/")
    prefix = "^" + re.escape(target) + r"\."
    if not rest:
        return prefix
    # What follows the entry is a slash or nothing: a suite's tests follow a slash, and so do a
    # parameterized test's cases (anchoring `noUnit\(value:\)$` skips none of them). So `Suite`
    # leaves `SuiteTwo` alone.
    return prefix + re.escape(rest) + "(/|$)"


def swift_test_arguments(entries):
    return [word for entry in entries for word in ("--skip", swift_test_pattern(entry))]


def xcodebuild_arguments(entries, target=None):
    return ["-skip-testing:" + entry for entry in entries if target is None or entry.split("/")[0] == target]


def main(argv, environment):
    modules = _modules()
    try:
        skipped = entries(environment.get("SKIP_TESTS", ""), test_targets(modules))
    except ValueError as error:
        print(f"test_skips.py: {error}", file=sys.stderr)
        return 1
    if argv[:1] == ["swift-test"]:
        words = swift_test_arguments(skipped)
    elif argv[:1] == ["xcodebuild"]:
        words = xcodebuild_arguments(skipped, argv[1] if len(argv) > 1 else None)
    else:
        print(__doc__, file=sys.stderr)
        return 2
    if words:
        print("\n".join(words))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:], os.environ))
