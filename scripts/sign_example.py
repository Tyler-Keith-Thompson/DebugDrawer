#!/usr/bin/env python3
"""Signs a Mac example app with a stable identity, so macOS keeps its privacy grants across builds.

Usage:
    python3 scripts/sign_example.py <path to .app>

macOS ties a privacy grant (Location, Files, Screen Recording...) to the app's designated
requirement. Bazel signs the example ad hoc, and an ad-hoc signature's designated requirement is
its cdhash, which changes with every build, so each rebuild is a new app to macOS and the grant is
gone. An Apple Development certificate's designated requirement names the bundle ID and the
certificate instead, which stay the same from build to build.

The identity is DEBUGDRAWER_SIGN_IDENTITY when set (any name or SHA-1 `codesign -s` takes; `-`
signs ad hoc), else the Keychain's first valid Apple Development identity, else ad hoc. Signing ad
hoc always prints a warning. The entitlements Bazel signed into the app are kept.
"""

import os
import re
import subprocess
import sys

ENVIRONMENT_VARIABLE = "DEBUGDRAWER_SIGN_IDENTITY"
AD_HOC = "-"
IDENTITY_LINE = re.compile(r'^\s*\d+\)\s+([0-9A-F]{40})\s+"(Apple Development: [^"]*)"', re.MULTILINE)
NO_IDENTITY = "no Apple Development signing identity in the Keychain"
FORCED = f"{ENVIRONMENT_VARIABLE} is {AD_HOC}"


def warning(reason):
    return (
        f"warning: {reason}, so the example is signed ad hoc. "
        "macOS will forget its privacy grants (Location, Files...) on every rebuild. "
        f"Set {ENVIRONMENT_VARIABLE} to a codesign identity to choose one."
    )


def apple_development_identities(find_identity_output):
    """(SHA-1, name) of each Apple Development identity `security find-identity -v` listed."""
    return IDENTITY_LINE.findall(find_identity_output)


def choose(environment, find_identity):
    """(the identity to sign with, a warning to print or None).

    `find_identity` is called only when the environment names no identity, and returns
    `security find-identity -v -p codesigning`'s output.
    """
    chosen = environment.get(ENVIRONMENT_VARIABLE, "")
    if chosen == AD_HOC:
        return AD_HOC, warning(FORCED)
    if chosen:
        return chosen, None
    identities = apple_development_identities(find_identity())
    if not identities:
        return AD_HOC, warning(NO_IDENTITY)
    # By SHA-1 rather than name: two certificates (an expired one beside its renewal) can share a name.
    return identities[0][0], None


def codesign_command(identity, app):
    # --deep re-signs the interposer dylib in Contents/Frameworks too, so the whole bundle carries
    # one identity and its seal covers the re-signed dylib. --timestamp=none: a development build needs no
    # trusted timestamp, and asking Apple's server for one would make every run need the network.
    return [
        "codesign", "--force", "--deep", "--timestamp=none",
        "--preserve-metadata=entitlements", "--sign", identity, app,
    ]


def find_identity():
    result = subprocess.run(
        ["security", "find-identity", "-v", "-p", "codesigning"],
        capture_output=True, text=True, check=False,
    )
    return result.stdout


def main(arguments):
    if len(arguments) != 1:
        raise SystemExit(__doc__)
    identity, warning = choose(os.environ, find_identity)
    if warning:
        print(warning, file=sys.stderr)
    subprocess.run(codesign_command(identity, arguments[0]), check=True)
    print(f"Signed {arguments[0]} with {'an ad-hoc signature' if identity == AD_HOC else identity}")


if __name__ == "__main__":
    main(sys.argv[1:])
