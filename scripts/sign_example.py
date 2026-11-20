#!/usr/bin/env python3
"""Signs a Mac example app with a stable identity, so macOS keeps its privacy grants across builds.

Usage:
    python3 scripts/sign_example.py [--app-group <name>] <path to .app>

macOS ties a privacy grant (Location, Files, Screen Recording...) to the app's designated
requirement. Bazel signs the example ad hoc, and an ad-hoc signature's designated requirement is
its cdhash, which changes with every build, so each rebuild is a new app to macOS and the grant is
gone. An Apple Development certificate's designated requirement names the bundle ID and the
certificate instead, which stay the same from build to build.

The identity is DEBUGDRAWER_SIGN_IDENTITY when set (any name or SHA-1 `codesign -s` takes; `-`
signs ad hoc), else the Keychain's first valid Apple Development identity, else ad hoc. Signing ad
hoc always prints a warning. The entitlements Bazel signed into the app are kept.

With --app-group, an app signed by a team also gets the app group `<team ID>.<name>` as its
`com.apple.security.application-groups`: on the Mac a group named after the signing team needs no
provisioning profile, so macOS gives both apps of the example sidecar pair the group's container
without asking whether one may "access data from other apps". Signed ad hoc, the app has no team
and gets no group, and the script says so.
"""

import os
import plistlib
import re
import subprocess
import sys
import tempfile

ENVIRONMENT_VARIABLE = "DEBUGDRAWER_SIGN_IDENTITY"
AD_HOC = "-"
IDENTITY_LINE = re.compile(r'^\s*\d+\)\s+([0-9A-F]{40})\s+"(Apple Development: [^"]*)"', re.MULTILINE)
NO_IDENTITY = "no Apple Development signing identity in the Keychain"
FORCED = f"{ENVIRONMENT_VARIABLE} is {AD_HOC}"
TEAM_LINE = re.compile(r"^TeamIdentifier=([A-Z0-9]{10})$", re.MULTILINE)
APP_GROUPS = "com.apple.security.application-groups"


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


def team_identifier(codesign_display_output):
    """The team `codesign -dv` names for a signed app, or None (ad hoc: `TeamIdentifier=not set`)."""
    match = TEAM_LINE.search(codesign_display_output)
    return match.group(1) if match else None


def with_app_group(entitlements, team, name):
    """`entitlements` with the app group `<team>.<name>` as the app's only group."""
    return {**entitlements, APP_GROUPS: [f"{team}.{name}"]}


def entitlements_command(identity, app, entitlements_path):
    # Not --deep: the first signing already signed the nested code, and the group is the app's own.
    return [
        "codesign", "--force", "--timestamp=none",
        "--entitlements", entitlements_path, "--sign", identity, app,
    ]


def add_app_group(identity, app, name):
    """Re-signs `app` into the app group `<team ID>.<name>`: the group, or None when it has no team."""
    display = subprocess.run(["codesign", "-dv", app], capture_output=True, text=True, check=True)
    team = team_identifier(display.stderr)
    if team is None:
        return None
    current = subprocess.run(
        ["codesign", "-d", "--entitlements", "-", "--xml", app], capture_output=True, check=True,
    ).stdout
    entitlements = with_app_group(plistlib.loads(current) if current.strip() else {}, team, name)
    with tempfile.NamedTemporaryFile(suffix=".entitlements") as file:
        file.write(plistlib.dumps(entitlements))
        file.flush()
        subprocess.run(entitlements_command(identity, app, file.name), check=True)
    return entitlements[APP_GROUPS][0]


def find_identity():
    result = subprocess.run(
        ["security", "find-identity", "-v", "-p", "codesigning"],
        capture_output=True, text=True, check=False,
    )
    return result.stdout


def main(arguments):
    app_group = None
    if len(arguments) == 3 and arguments[0] == "--app-group":
        app_group, arguments = arguments[1], arguments[2:]
    if len(arguments) != 1:
        raise SystemExit(__doc__)
    app = arguments[0]
    identity, warning = choose(os.environ, find_identity)
    if warning:
        print(warning, file=sys.stderr)
    subprocess.run(codesign_command(identity, app), check=True)
    print(f"Signed {app} with {'an ad-hoc signature' if identity == AD_HOC else identity}")
    if app_group is None:
        return
    group = None if identity == AD_HOC else add_app_group(identity, app, app_group)
    if group:
        print(f"Signed {app} into the app group {group}")
    else:
        print(f"{app} has no signing team, so no app group: the example sidecar pair shares a folder in Caches instead")


if __name__ == "__main__":
    main(sys.argv[1:])
