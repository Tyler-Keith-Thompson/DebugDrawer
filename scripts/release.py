#!/usr/bin/env python3
"""The gates `just deploy` passes before it tags a release.

A release needs an entry in CHANGELOG.md under its version's heading, and its public API must not
break the previous release's, as `swift package diagnose-api-breaking-changes` judges it, unless
the bump is major or the release is deployed with `allow-breaking`. The entry, plus any breaks the
release carries, becomes the GitHub release's notes.

    release.py next-version <major|minor|patch>
    release.py notes <version>
    release.py gate <major|minor|patch> --swift "<swift command>" --notes-file <path> [--allow-breaking]

The functions above `main` are pure, and scripts/release_test.py checks them.
"""

import argparse
import dataclasses
import os
import re
import shlex
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHANGELOG = os.path.join(ROOT, "CHANGELOG.md")
BUMPS = ("major", "minor", "patch")
FIRST_VERSION = "v0.0.1"


@dataclasses.dataclass(frozen=True)
class Version:
    """A release version, written `vMAJOR.MINOR.PATCH` in tags and `MAJOR.MINOR.PATCH` in CHANGELOG.md."""

    major: int
    minor: int
    patch: int

    @staticmethod
    def parse(text):
        """The version a tag or heading names (`v0.1.1` or `0.1.1`). Raises ValueError for anything else."""
        match = re.fullmatch(r"v?(\d+)\.(\d+)\.(\d+)", text.strip())
        if not match:
            raise ValueError(f"not a version: {text!r}")
        return Version(*(int(part) for part in match.groups()))

    def bumped(self, bump):
        """The next version for a bump. Raises ValueError for a bump other than major, minor or patch."""
        if bump == "major":
            return Version(self.major + 1, 0, 0)
        if bump == "minor":
            return Version(self.major, self.minor + 1, 0)
        if bump == "patch":
            return Version(self.major, self.minor, self.patch + 1)
        raise ValueError(f"unknown bump {bump!r}: use major, minor or patch")

    @property
    def tag(self):
        return f"v{self.major}.{self.minor}.{self.patch}"

    @property
    def number(self):
        return f"{self.major}.{self.minor}.{self.patch}"


def next_version(latest_tag, bump):
    """The version a bump releases after the latest tag, or the first version when there is no tag."""
    if not latest_tag:
        return Version.parse(FIRST_VERSION)
    return Version.parse(latest_tag).bumped(bump)


def changelog_entry(changelog, version):
    """The body of CHANGELOG.md's entry for a version, or None when it has no entry.

    The entry is the text under a `## [0.1.2]` heading (a date may follow it, `## [0.1.2] - 2026-11-17`),
    up to the next `## ` heading. A heading with nothing under it is no entry.
    """
    heading = re.compile(rf"^## \[v?{re.escape(version.number)}\](?:\s|$)")
    lines = changelog.splitlines()
    for index, line in enumerate(lines):
        if heading.match(line):
            body = []
            for following in lines[index + 1:]:
                if following.startswith("## "):
                    break
                body.append(following)
            text = "\n".join(body).strip()
            return text or None
    return None


@dataclasses.dataclass(frozen=True)
class Breakage:
    """One API break diagnose-api-breaking-changes reports, in the module it found it in."""

    module: str
    description: str


def parse_breakages(output):
    """The breaks in diagnose-api-breaking-changes' summary, which lists each module's under a
    `N breaking change(s) detected in Module:` line. The compiler warnings it prints first repeat
    them, so only the summary is read."""
    breakages = []
    module = None
    summary = re.compile(r"^\d+ breaking changes? detected in (\S+):$")
    for line in output.splitlines():
        header = summary.match(line.strip())
        if header:
            module = header.group(1)
            continue
        if not line.startswith(" "):
            module = None
        elif module and "API breakage:" in line:
            breakages.append(Breakage(module, line.split("API breakage:", 1)[1].strip()))
    return breakages


@dataclasses.dataclass(frozen=True)
class Decision:
    """Whether a release may be tagged, and why."""

    proceed: bool
    reason: str


def decide(bump, breakages, allow_breaking):
    """Whether a release with these API breaks may be tagged: with none, after a major bump, or when
    the release is deployed with `allow-breaking`."""
    if not breakages:
        return Decision(True, "No API breaks since the previous release.")
    count = f"{len(breakages)} API break{'s' if len(breakages) != 1 else ''}"
    if bump == "major":
        return Decision(True, f"{count}, allowed by the major bump.")
    if allow_breaking:
        return Decision(True, f"{count}, allowed by allow-breaking; they go into the release notes.")
    return Decision(False, f"{count} in a {bump} release. Make it major, or deploy with allow-breaking "
                           f"(`just deploy {bump} allow-breaking`) to release them knowingly.")


def release_notes(entry, breakages):
    """The GitHub release's notes: the changelog entry, then the API breaks the release carries."""
    if not breakages:
        return entry + "\n"
    lines = [entry, "", "### API breaks", ""]
    lines += [f"- `{breakage.module}`: {breakage.description}" for breakage in breakages]
    return "\n".join(lines) + "\n"


def latest_tag():
    result = subprocess.run(["git", "describe", "--tags", "--abbrev=0", "--match", "v*"],
                            cwd=ROOT, capture_output=True, text=True)
    return result.stdout.strip() if result.returncode == 0 else ""


def read_changelog():
    try:
        with open(CHANGELOG) as file:
            return file.read()
    except FileNotFoundError:
        return ""


def diagnose(swift, baseline):
    """Runs diagnose-api-breaking-changes against a tag. Its baseline build is kept under .build, so
    a second run against the same tag (a dry run, then the release) skips it. Every library product
    is compared: their only package dependency, OSLogClient, builds on macOS, and the Apple-only
    test packages are not in any library product."""
    command = shlex.split(swift) + [
        "package", "diagnose-api-breaking-changes", baseline,
        "--baseline-dir", os.path.join(ROOT, ".build", "api-baseline", baseline),
    ]
    print(f"Comparing the public API with {baseline}: {' '.join(command)}", flush=True)
    result = subprocess.run(command, cwd=ROOT, capture_output=True, text=True)
    output = result.stdout + result.stderr
    breakages = parse_breakages(output)
    # It exits non-zero when it finds a break; non-zero with none parsed means it failed to run.
    if result.returncode != 0 and not breakages:
        sys.stderr.write(output)
        sys.exit(f"Error: diagnose-api-breaking-changes failed (exit {result.returncode}); see its output above.")
    return breakages


def gate(arguments):
    previous = latest_tag()
    version = next_version(previous, arguments.bump)
    print(f"Releasing {version.tag} ({arguments.bump} after {previous or 'no release'})")

    entry = changelog_entry(read_changelog(), version)
    if entry is None:
        sys.exit(f"Error: CHANGELOG.md has no entry for {version.number}. Add a `## [{version.number}] - <date>` "
                 "heading (the Unreleased section, renamed) with what the release changes, and commit it first.")
    print(f"CHANGELOG.md has an entry for {version.number}.")

    breakages = diagnose(arguments.swift, previous) if previous else []
    for breakage in breakages:
        print(f"  API break in {breakage.module}: {breakage.description}")
    decision = decide(arguments.bump, breakages, arguments.allow_breaking)
    print(decision.reason)
    if not decision.proceed:
        sys.exit(1)

    os.makedirs(os.path.dirname(os.path.abspath(arguments.notes_file)), exist_ok=True)
    with open(arguments.notes_file, "w") as file:
        file.write(release_notes(entry, breakages))
    print(f"Release notes: {arguments.notes_file}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", required=True)

    next_parser = commands.add_parser("next-version", help="print the version a bump releases")
    next_parser.add_argument("bump", choices=BUMPS)

    notes_parser = commands.add_parser("notes", help="print CHANGELOG.md's entry for a version")
    notes_parser.add_argument("version")

    gate_parser = commands.add_parser("gate", help="check the changelog and the API before tagging")
    gate_parser.add_argument("bump", choices=BUMPS)
    gate_parser.add_argument("--swift", required=True, help="the swift command, as the justfile's SWIFT")
    gate_parser.add_argument("--notes-file", required=True, help="where to write the release notes")
    gate_parser.add_argument("--allow-breaking", action="store_true",
                             help="release API breaks in a minor or patch release")

    arguments = parser.parse_args()
    if arguments.command == "next-version":
        print(next_version(latest_tag(), arguments.bump).tag)
    elif arguments.command == "notes":
        entry = changelog_entry(read_changelog(), Version.parse(arguments.version))
        if entry is None:
            sys.exit(f"Error: CHANGELOG.md has no entry for {arguments.version}.")
        print(entry)
    else:
        gate(arguments)


if __name__ == "__main__":
    main()
