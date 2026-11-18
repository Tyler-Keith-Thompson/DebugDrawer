"""First-party Swift rule wrappers.

Every first-party `swift_library` / `swift_test` / `swift_binary` loads from here instead of
`@rules_swift//swift:swift.bzl`. The wrappers flip rules_swift features so our
own code is held to a stricter warnings policy than third-party code:

  * `.bazelrc` enables `swift.suppress_warnings` globally, so swiftc gets
    `-suppress-warnings` and dependencies build without noise.
  * Each first-party target disables that feature and enables
    `swift.treat_warnings_as_errors`, so swiftc gets `-warnings-as-errors`
    for our modules.

Net effect: dependencies build quietly, our own warnings fail the build.

`swift_test` also runs each test process in a home folder of its own (`_home_folder_test`), so
nothing a test installs writes into the developer's `~/Library`.
"""

load(
    "@rules_swift//swift:swift.bzl",
    _swift_binary = "swift_binary",
    _swift_library = "swift_library",
    _swift_test = "swift_test",
)

_FIRST_PARTY_FEATURES = [
    "-swift.suppress_warnings",
    "swift.treat_warnings_as_errors",
    # Hands swiftc an exact map of module name to path instead of a list of directories to
    # search. rules_swift otherwise passes one `-I` per Bazel package, so a module could import
    # something it never declared a dependency on, and SwiftPM (which is strict about this)
    # would then fail where Bazel passed.
    "swift.use_explicit_swift_module_map",
    # Tracks each module's .swiftsourceinfo as an output, so //:docs can read source locations
    # from it (see docc.bzl). The file holds absolute paths; nothing but the docs reads it.
    "swift.emit_swiftsourceinfo",
]

# Package.swift uses tools version 6.3, so SwiftPM compiles in the Swift 6 language mode.
# rules_swift defaults to Swift 5, under which concurrency checking differs, so first-party
# targets are pinned to match the published package.
_FIRST_PARTY_COPTS = ["-swift-version", "6"]

# All first-party modules belong to one Swift package. SwiftPM knows this from the manifest;
# Bazel has to be told, or `package` access level and retroactive-conformance checks disagree
# between the two build systems.
_PACKAGE_NAME = "debugdrawer"

def swift_library(name, features = [], copts = [], **kwargs):
    _swift_library(
        name = name,
        features = features + _FIRST_PARTY_FEATURES,
        copts = copts + _FIRST_PARTY_COPTS,
        package_name = _PACKAGE_NAME,
        **kwargs
    )

# Plugins keep their files in Application Support and Caches under the home folder, which on macOS
# Foundation reads from CFFIXED_USER_HOME, never from HOME. A test target's `env` can't name the
# run's TEST_TMPDIR, and a relative CFFIXED_USER_HOME hangs AppKit's view tests, so a runner script
# sets it to a new folder in TEST_TMPDIR and runs the swift_test binary; every exit test's child
# inherits it. A runner rather than a hook in the tests: the README examples run verbatim, with
# the plugins' default storage.
_RUNNER = """#!/bin/sh
set -eu
CFFIXED_USER_HOME="$(mktemp -d "${{TEST_TMPDIR:-${{TMPDIR:-/tmp}}}}/home.XXXXXX")"
export CFFIXED_USER_HOME
exec "./{binary}" "$@"
"""

def _home_folder_test_impl(ctx):
    binary = ctx.attr.binary
    executable = binary[DefaultInfo].files_to_run.executable
    runner = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(runner, _RUNNER.format(binary = executable.short_path), is_executable = True)
    providers = [
        DefaultInfo(
            executable = runner,
            runfiles = ctx.runfiles(files = [executable]).merge(binary[DefaultInfo].default_runfiles),
        ),
        binary[RunEnvironmentInfo],
        coverage_common.instrumented_files_info(ctx, dependency_attributes = ["binary"]),
    ]
    if testing.ExecutionInfo in binary:
        providers.append(binary[testing.ExecutionInfo])
    return providers

_home_folder_test = rule(
    implementation = _home_folder_test_impl,
    doc = "Runs a swift_test binary with CFFIXED_USER_HOME set to a new folder in TEST_TMPDIR.",
    attrs = {"binary": attr.label(executable = True, cfg = "target", mandatory = True)},
    test = True,
)

def swift_test(name, features = [], copts = [], tags = [], size = None, visibility = None, **kwargs):
    """A swift_test, `<name>Binary`, that `bazel test` runs as `<name>` in a home folder of its own."""
    _swift_test(
        name = name + "Binary",
        features = features + _FIRST_PARTY_FEATURES,
        copts = copts + _FIRST_PARTY_COPTS,
        package_name = _PACKAGE_NAME,
        # `manual`: `bazel test //...` runs it through `name` alone.
        tags = tags + ["manual"],
        size = size,
        **kwargs
    )
    _home_folder_test(
        name = name,
        binary = name + "Binary",
        tags = tags,
        size = size,
        testonly = True,
        visibility = visibility,
    )

def swift_binary(name, features = [], copts = [], **kwargs):
    _swift_binary(
        name = name,
        features = features + _FIRST_PARTY_FEATURES,
        copts = copts + _FIRST_PARTY_COPTS,
        package_name = _PACKAGE_NAME,
        **kwargs
    )
