#!/usr/bin/env python3
"""Fails when a public symbol in a module's symbol graph has no doc comment.

    python3 documentation_coverage.py <symbol graph dir> <stamp file>

DocC's `--warnings-as-errors` fails on a link that doesn't resolve, but not on a symbol with no
documentation, and its `--experimental-documentation-coverage` only writes a report. So
`docc_archive(require_documentation = True)` (tools/docc.bzl) runs this over the symbol graph
first, and the archive, and so `just docs`, fails while any public symbol is undocumented.

A symbol counts as documented when it has a doc comment of its own, or one it inherits from the
requirement it implements in another module (a view's `body` takes SwiftUI's `View.body`), which
DocC shows on its page. Left out: extension blocks, which DocC lists under the extended type, and
the members a protocol extension or the compiler supplies (`::SYNTHESIZED::`), which are
documented where they are declared.

On success the stamp file is written, as the action's output; on failure each undocumented
symbol is printed and the exit status is 1.
"""

import glob
import json
import os
import sys

# Extension blocks, emitted with `-emit-extension-block-symbols`; their members are checked.
EXTENSION_BLOCK = "swift.extension"


def undocumented(symbol_graph):
    """The undocumented symbols in one symbol graph, as `kind path` lines."""
    found = []
    for symbol in symbol_graph.get("symbols", []):
        kind = symbol["kind"]["identifier"]
        if kind == EXTENSION_BLOCK or "::SYNTHESIZED::" in symbol["identifier"]["precise"]:
            continue
        lines = symbol.get("docComment", {}).get("lines", [])
        if not any(line.get("text", "").strip() for line in lines):
            found.append(f"{symbol['kind']['displayName']} {'.'.join(symbol['pathComponents'])}")
    return found


def main(arguments):
    if len(arguments) != 2:
        print(__doc__.strip().split("\n\n")[1], file=sys.stderr)
        return 2
    graph_dir, stamp = arguments
    paths = sorted(glob.glob(os.path.join(graph_dir, "*.symbols.json")))
    if not paths:
        print(f"error: no symbol graphs in {graph_dir}", file=sys.stderr)
        return 1
    missing = []
    for path in paths:
        with open(path) as f:
            missing += undocumented(json.load(f))
    if missing:
        print(f"error: public symbols with no doc comment ({len(missing)}):")
        for line in sorted(set(missing)):
            print(f"  {line}")
        return 1
    with open(stamp, "w") as f:
        f.write("documented\n")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
