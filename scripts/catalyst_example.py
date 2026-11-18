#!/usr/bin/env python3
"""Builds the iOS example app (Example/iOS) as a Mac Catalyst app, and launches it.

Usage:
    python3 scripts/catalyst_example.py build                 # generate the package, build, bundle
    python3 scripts/catalyst_example.py launch [app args...]  # open the bundle in the background

Bazel has no Mac Catalyst platform (tools/catalyst.bzl), so SwiftPM builds it: a throwaway package
under .build/catalyst-example, which xcodebuild builds for Mac Catalyst. Nothing in it is written by
hand. It is derived from the example's sources:

- the app is an executable target of every Example/iOS/*.swift;
- each `import` in those files names a product of this package (`DebugDrawer...`), an example
  library (`ExampleX`, a target of Example/X/*.swift, as in Example/BUILD.bazel) or an SDK module,
  which needs nothing; an example library's own imports are followed the same way;
- the app also links the libraries in LINKED_LIBRARIES, which Example/BUILD.bazel links without
  an import.

The executable is then wrapped in an ad-hoc signed .app bundle with Example/iOS's identity and
resources, as Xcode would for a Catalyst app.

CATALYST_EXAMPLE_EXCLUDE (comma-separated paths under the repository, such as
Example/iOS/ExampleHang.swift) leaves those files out of the package. It exists only to show that
the build fails when a file the example needs is missing.
"""

import os
import plistlib
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass, field

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORK = os.path.join(ROOT, ".build", "catalyst-example")
APP_TARGET = "ExampleApp_iOS"
APP_DIRECTORY = os.path.join("Example", "iOS")
APP_BUNDLE = "DebugDrawerExample.app"

# Libraries the app links without importing them: Example/BUILD.bazel embeds the interposer as a
# framework, and unsafeInstallDiskIOWithInterposing() finds it with dlsym.
LINKED_LIBRARIES = ["DebugDrawerDiskIOInterposer"]

IMPORT = re.compile(r"^\s*(?:@[\w()]+\s+)*import\s+(?:(?:struct|class|enum|protocol|func|var|let|typealias)\s+)?(\w+)", re.MULTILINE)
LIBRARY_PRODUCT = re.compile(r'\.library\(name:\s*"(\w+)"')


@dataclass
class Target:
    name: str
    directory: str  # relative to the repository
    sources: list = field(default_factory=list)  # relative to the repository
    products: list = field(default_factory=list)  # products of the DebugDrawer package
    libraries: list = field(default_factory=list)  # example library targets


def imports(path):
    with open(path, encoding="utf-8") as file:
        return IMPORT.findall(file.read())


def package_products(root):
    with open(os.path.join(root, "Package.swift"), encoding="utf-8") as file:
        return set(LIBRARY_PRODUCT.findall(file.read()))


def swift_sources(root, directory, exclude):
    absolute = os.path.join(root, directory)
    names = sorted(name for name in os.listdir(absolute) if name.endswith(".swift"))
    return [os.path.join(directory, name) for name in names if os.path.join(directory, name) not in exclude]


def plan(root, exclude=()):
    """The package's targets, app first: each with its sources and what it depends on."""
    exclude = {os.path.normpath(path) for path in exclude}
    products = package_products(root)
    targets = {}

    def resolve(name, directory):
        target = Target(name, directory, swift_sources(root, directory, exclude))
        targets[name] = target
        found = sorted({module for source in target.sources for module in imports(os.path.join(root, source))})
        for module in found:
            if module in products:
                target.products.append(module)
            elif module.startswith("DebugDrawer"):
                raise SystemExit(f"{directory} imports {module}, which is no product of Package.swift")
            elif module.startswith("Example"):
                library = os.path.join("Example", module[len("Example"):])
                if not os.path.isdir(os.path.join(root, library)):
                    raise SystemExit(f"{directory} imports {module}, but {library} doesn't exist")
                target.libraries.append(module)
                if module not in targets:
                    resolve(module, library)
        return target

    app = resolve(APP_TARGET, APP_DIRECTORY)
    for library in LINKED_LIBRARIES:
        if library not in products:
            raise SystemExit(f"{library} is no product of Package.swift")
        if library not in app.products:
            app.products.append(library)
    return [app] + [target for name, target in targets.items() if name != APP_TARGET]


def package_swift(root, targets):
    lines = [
        "// swift-tools-version: 6.3",
        "// Written by scripts/catalyst_example.py from Example's sources; don't edit.",
        "import PackageDescription",
        "",
        "let package = Package(",
        '    name: "CatalystExample",',
        "    platforms: [.iOS(.v17), .macOS(.v15)],",
        f'    dependencies: [.package(name: "DebugDrawer", path: "{root}")],',
        "    targets: [",
    ]
    for target in targets:
        kind = "executableTarget" if target.name == APP_TARGET else "target"
        lines.append(f'        .{kind}(name: "{target.name}", dependencies: [')
        lines += [f'            "{library}",' for library in target.libraries]
        lines += [f'            .product(name: "{product}", package: "DebugDrawer"),' for product in target.products]
        lines.append("        ]),")
    lines += ["    ]", ")", ""]
    return "\n".join(lines)


def generate(root, work, exclude=()):
    """Writes the package: a Sources/<target> directory of symlinks per target, and Package.swift."""
    targets = plan(root, exclude)
    sources = os.path.join(work, "Sources")
    shutil.rmtree(sources, ignore_errors=True)
    for target in targets:
        directory = os.path.join(sources, target.name)
        os.makedirs(directory)
        for source in target.sources:
            os.symlink(os.path.join(root, source), os.path.join(directory, os.path.basename(source)))
    with open(os.path.join(work, "Package.swift"), "w", encoding="utf-8") as file:
        file.write(package_swift(root, targets))
    return targets


def run(*command, cwd=None):
    subprocess.run(command, cwd=cwd, check=True)


def build():
    exclude = [path for path in os.environ.get("CATALYST_EXAMPLE_EXCLUDE", "").split(",") if path]
    os.makedirs(WORK, exist_ok=True)
    targets = generate(ROOT, WORK, exclude)
    for target in targets:
        print(f"{target.name}: {len(target.sources)} files from {target.directory}", flush=True)
    if exclude:
        print(f"Left out (CATALYST_EXAMPLE_EXCLUDE): {', '.join(exclude)}", flush=True)

    derived = os.path.join(WORK, "DerivedData")
    # Not SWIFT_TREAT_WARNINGS_AS_ERRORS: it would apply to OSLogClient, which builds with warnings
    # suppressed. `just build-spm` holds the libraries to that.
    run("xcodebuild", "build", "-quiet", "-scheme", "CatalystExample",
        "-destination", "platform=macOS,variant=Mac Catalyst", "-derivedDataPath", derived, cwd=WORK)

    products = os.path.join(derived, "Build", "Products", "Debug-maccatalyst")
    app = os.path.join(WORK, APP_BUNDLE)
    shutil.rmtree(app, ignore_errors=True)
    macos = os.path.join(app, "Contents", "MacOS")
    resources = os.path.join(app, "Contents", "Resources")
    frameworks = os.path.join(app, "Contents", "Frameworks")
    os.makedirs(macos)
    os.makedirs(resources)
    executable = os.path.join(macos, APP_TARGET)
    shutil.copy2(os.path.join(products, APP_TARGET), executable)
    for name in sorted(os.listdir(products)):
        if name.endswith(".bundle"):
            shutil.copytree(os.path.join(products, name), os.path.join(resources, name), symlinks=True)
    # The localized tables the Localization plugin reads from the main bundle, as ios_application
    # copies them.
    app_resources = os.path.join(ROOT, APP_DIRECTORY, "Resources")
    for name in sorted(os.listdir(app_resources)):
        shutil.copytree(os.path.join(app_resources, name), os.path.join(resources, name))
    # The dynamic libraries (LINKED_LIBRARIES), which xcodebuild builds as frameworks the
    # executable loads from @rpath.
    package_frameworks = os.path.join(products, "PackageFrameworks")
    if os.path.isdir(package_frameworks):
        os.makedirs(frameworks)
        for name in sorted(os.listdir(package_frameworks)):
            shutil.copytree(os.path.join(package_frameworks, name), os.path.join(frameworks, name), symlinks=True)
        load_commands = subprocess.run(["otool", "-l", executable], check=True, capture_output=True, text=True).stdout
        if "@executable_path/../Frameworks" not in load_commands:
            run("install_name_tool", "-add_rpath", "@executable_path/../Frameworks", executable)

    with open(os.path.join(ROOT, APP_DIRECTORY, "Info.plist"), "rb") as file:
        info = plistlib.load(file)
    info["CFBundleExecutable"] = APP_TARGET
    info["CFBundleSupportedPlatforms"] = ["MacOSX"]
    # The iPad idiom: Catalyst's "Scaled to match iPad".
    info["UIDeviceFamily"] = [2]
    with open(os.path.join(app, "Contents", "Info.plist"), "wb") as file:
        plistlib.dump(info, file)
    if os.path.isdir(frameworks):
        for name in sorted(os.listdir(frameworks)):
            run("codesign", "--force", "--sign", "-", os.path.join(frameworks, name))
    run("codesign", "--force", "--sign", "-", app)
    print(f"Built {app}")


def launch(arguments):
    app = os.path.join(WORK, APP_BUNDLE)
    if not os.path.isdir(app):
        raise SystemExit(f"{app} doesn't exist; run `{sys.argv[0]} build` first")
    # -g keeps the app behind the frontmost one; -n starts a new instance each run.
    run("open", "-g", "-n", app, "--args", *arguments)
    print(f"Launched {app}")


def main(arguments):
    if arguments[:1] == ["build"] and len(arguments) == 1:
        build()
    elif arguments[:1] == ["launch"]:
        launch(arguments[1:])
    else:
        raise SystemExit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
