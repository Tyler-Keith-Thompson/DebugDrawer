#!/usr/bin/env python3
"""Fails when a public symbol of a library module is missing from its release build.

Every drawer entry point is `#if DEBUG`, and every public API keeps a release stand-in so callers
compile unchanged in release (the charter's rules). This compares each module's public symbol
graph built in debug with the one built in release: a symbol, or a conformance, that debug has
and release lacks is an API a host's release build would fail to find.

    release_api.py check --swift "<swift command>"
    release_api.py compare <debug symbol graph dir> <release symbol graph dir>

`check` builds the package twice through SwiftPM, emitting symbol graphs, then compares them.
Symbols are matched by their precise identifier (the USR), which spells the declaration's
context, name and type, so a stand-in matches only when callers see the same signature.

The functions above `main` are pure, and scripts/release_api_test.py checks them.
"""

import argparse
import glob
import json
import os
import shlex
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SOURCES = os.path.join(ROOT, "Sources")

# Members a protocol extension supplies carry this in their USR; extension blocks (emitted with
# `-emit-extension-block-symbols`) have this kind.
SYNTHESIZED = "::SYNTHESIZED::"
EXTENSION_BLOCK = "swift.extension"

# Relationships a caller relies on: `x as SomeProtocol`, `@ObservedObject`, a class hierarchy.
CALLER_VISIBLE_RELATIONSHIPS = ("conformsTo", "inheritsFrom")


def surface(symbol_graph):
    """A symbol graph's public surface, as a dictionary from what identifies each entry (a symbol's
    USR, or a relationship's source, kind and target USRs) to the line printed when it is missing
    (`Structure NetworkPlugin`, `NetworkStore conformsTo Combine.ObservableObject`)."""
    names = {}
    found = {}
    for symbol in symbol_graph.get("symbols", []):
        usr = symbol["identifier"]["precise"]
        path = ".".join(symbol["pathComponents"])
        names[usr] = path
        # A member a protocol extension supplies (`::SYNTHESIZED::`) comes with the conformance,
        # which is compared below; extension blocks are compared through their members.
        if SYNTHESIZED in usr or symbol["kind"]["identifier"] == EXTENSION_BLOCK:
            continue
        found[usr] = f"{symbol['kind']['displayName']} {path}"
    for relationship in symbol_graph.get("relationships", []):
        kind = relationship["kind"]
        if kind not in CALLER_VISIBLE_RELATIONSHIPS:
            continue
        source, target = relationship["source"], relationship["target"]
        key = f"{source} {kind} {target}"
        fallback = relationship.get("targetFallback", target)
        found[key] = f"{names.get(source, source)} {kind} {names.get(target, fallback)}"
    return found


def missing_in_release(debug_graphs, release_graphs):
    """What the debug graphs declare and the release graphs don't, as sorted lines per module.

    Both arguments map a module name to its symbol graphs (the module's own and its extensions of
    other modules). A module release doesn't build at all is missing whole.
    """
    missing = {}
    for module in sorted(debug_graphs):
        debug = {}
        for graph in debug_graphs[module]:
            debug.update(surface(graph))
        release = {}
        for graph in release_graphs.get(module, []):
            release.update(surface(graph))
        lines = sorted({line for key, line in debug.items() if key not in release})
        if lines:
            missing[module] = lines
    return missing


def library_modules():
    """The library modules under Sources/, by directory name."""
    return sorted(
        name for name in os.listdir(SOURCES)
        if os.path.isdir(os.path.join(SOURCES, name)) and not name.startswith(".")
    )


def read_graphs(directory, modules):
    """The symbol graphs in a directory for each module: `M.symbols.json` and `M@Other.symbols.json`."""
    graphs = {}
    for module in modules:
        paths = sorted(
            glob.glob(os.path.join(directory, f"{module}.symbols.json"))
            + glob.glob(os.path.join(directory, f"{module}@*.symbols.json"))
        )
        loaded = []
        for path in paths:
            with open(path) as f:
                loaded.append(json.load(f))
        graphs[module] = loaded
    return graphs


def build_graphs(swift, configuration, directory):
    """Builds the package in a configuration, writing every module's symbol graph to `directory`."""
    os.makedirs(directory, exist_ok=True)
    for stale in glob.glob(os.path.join(directory, "*.symbols.json")):
        os.remove(stale)
    command = shlex.split(swift) + [
        "build", "-c", configuration,
        "-Xswiftc", "-emit-symbol-graph",
        "-Xswiftc", "-emit-symbol-graph-dir", "-Xswiftc", directory,
    ]
    print(f"Building {configuration} symbol graphs: {shlex.join(command)}", flush=True)
    subprocess.run(command, cwd=ROOT, check=True)


def report(missing):
    """Prints what is missing and returns the exit status."""
    if not missing:
        print("Every public symbol of every library module exists in release builds.")
        return 0
    count = sum(len(lines) for lines in missing.values())
    print(f"error: public API missing from release builds ({count}); give each a release stand-in:")
    for module, lines in missing.items():
        print(f"  {module}:")
        for line in lines:
            print(f"    {line}")
    return 1


def main():
    parser = argparse.ArgumentParser(description=__doc__.strip().split("\n\n")[0])
    commands = parser.add_subparsers(dest="command", required=True)
    check = commands.add_parser("check", help="build debug and release through SwiftPM and compare")
    check.add_argument("--swift", default="swift", help="the swift command to run")
    check.add_argument("--graphs", default=os.path.join(ROOT, ".build", "release-api"),
                       help="where to write the symbol graphs")
    compare = commands.add_parser("compare", help="compare two directories of symbol graphs")
    compare.add_argument("debug")
    compare.add_argument("release")
    arguments = parser.parse_args()

    modules = library_modules()
    if arguments.command == "check":
        debug_dir = os.path.join(arguments.graphs, "debug")
        release_dir = os.path.join(arguments.graphs, "release")
        build_graphs(arguments.swift, "debug", debug_dir)
        build_graphs(arguments.swift, "release", release_dir)
    else:
        debug_dir, release_dir = arguments.debug, arguments.release
    return report(missing_in_release(read_graphs(debug_dir, modules), read_graphs(release_dir, modules)))


if __name__ == "__main__":
    sys.exit(main())
