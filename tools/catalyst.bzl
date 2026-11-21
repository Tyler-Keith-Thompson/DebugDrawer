"""Mac Catalyst: `catalyst_build_test` compiles Swift libraries for it, `catalyst_test` runs tests there.

Bazel and rules_apple have no Mac Catalyst platform: rules_apple has no Catalyst rules, apple_support
registers no Catalyst CPU, and `--apple_platform_type=catalyst --catalyst_cpus=arm64` crashes
Bazel's analysis ("No supported apple platform registered for target cpu catalyst_arm64"). A
Catalyst build is a macOS build with an iOS target triple, though: the macOS SDK, the
`<arch>-apple-ios<version>-macabi` target and the SDK's iOSSupport frameworks. So both rules build
their targets in the macOS configuration changed by one transition:

- rules_swift's `copt` targets the Catalyst triple, so swiftc compiles Catalyst code, where
  `os(iOS)` and `targetEnvironment(macCatalyst)` hold;
- `linkopt` targets it too, with the iOSSupport frameworks and Swift libraries to link against;
- apple_support's `default_required_flags` feature is off. It ends every link with
  `-target <arch>-apple-macosx<version>`, after the linkopts, so the link would be the Mac's; the
  `-no-canonical-prefixes` it also passes moves to the linkopts. Bazel sets the Xcode environment
  its entries hold on Apple actions itself, so nothing else is lost. A C or Objective-C compile
  in this configuration would get no target at all, which is why only Swift builds here;
- `//tools:catalyst_build` is true, so `select`s on `//tools:catalyst` leave out the packages that
  don't build for Catalyst (APPLE_ONLY_PACKAGE_EXCLUDED_PLATFORMS in scripts/modules.py). That
  config setting also names `@platforms//os:macos`, so it wins over a macOS branch.

One transition for both rules, so a library compiled for a `catalyst_build_test` is the one a
`catalyst_test` links.
"""

_COPT = "@rules_swift//swift:copt"
_LINKOPT = "//command_line_option:linkopt"
_FEATURES = "//command_line_option:features"
_CPU = "//command_line_option:cpu"
_CATALYST_BUILD = "//tools:catalyst_build"

def _catalyst_transition_impl(settings, attr):
    cpu = settings[_CPU]
    if not cpu.startswith("darwin_"):
        fail("Mac Catalyst builds on a Mac only; the target CPU is {}".format(cpu))
    triple = "{}-apple-ios{}-macabi".format(cpu.removeprefix("darwin_"), attr.minimum_os_version)
    return {
        _COPT: settings[_COPT] + [
            "-target",
            triple,
            # UIKit and the iOS flavor of SwiftUI live in the macOS SDK's iOSSupport tree; swiftc
            # finds the iOSSupport library paths from the target, but not its frameworks.
            "-Fsystem",
            "__BAZEL_XCODE_SDKROOT__/System/iOSSupport/System/Library/Frameworks",
        ],
        _LINKOPT: settings[_LINKOPT] + [
            "-no-canonical-prefixes",
            "-target",
            triple,
            # The linker, unlike swiftc, is told every iOSSupport path: the frameworks, their Swift
            # overlays, and the toolchain's Catalyst Swift libraries.
            "-F__BAZEL_XCODE_SDKROOT__/System/iOSSupport/System/Library/Frameworks",
            "-L__BAZEL_XCODE_SDKROOT__/System/iOSSupport/usr/lib/swift",
            "-L__BAZEL_XCODE_DEVELOPER_DIR__/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/maccatalyst",
        ],
        _FEATURES: settings[_FEATURES] + ["-default_required_flags"],
        _CATALYST_BUILD: True,
    }

_catalyst_transition = transition(
    implementation = _catalyst_transition_impl,
    inputs = [_CPU, _COPT, _LINKOPT, _FEATURES],
    outputs = [_COPT, _LINKOPT, _FEATURES, _CATALYST_BUILD],
)

_ALLOWLIST = attr.label(default = "@bazel_tools//tools/allowlists/function_transition_allowlist")

def _catalyst_build_setting_impl(_ctx):
    return []

catalyst_build_setting = rule(
    implementation = _catalyst_build_setting_impl,
    build_setting = config.bool(),
    doc = "True in the configuration the Mac Catalyst rules build their targets in.",
)

_PASSING_TEST_SCRIPT = """\
#!/bin/bash
exit 0
"""

def _catalyst_build_test_impl(ctx):
    # Like rules_apple's `<platform>_build_test`: the test passes once its targets build.
    ctx.actions.write(output = ctx.outputs.executable, content = _PASSING_TEST_SCRIPT, is_executable = True)
    return [DefaultInfo(
        executable = ctx.outputs.executable,
        runfiles = ctx.runfiles(transitive_files = depset(transitive = [t[DefaultInfo].files for t in ctx.attr.targets])),
    )]

catalyst_build_test = rule(
    implementation = _catalyst_build_test_impl,
    doc = "Builds `targets` for Mac Catalyst, so `bazel build //...` checks they compile there.",
    attrs = {
        "minimum_os_version": attr.string(
            mandatory = True,
            doc = "The iOS version the Catalyst target triple names (`17.0`).",
        ),
        "targets": attr.label_list(
            allow_empty = False,
            cfg = _catalyst_transition,
            doc = "The Swift libraries to compile for Mac Catalyst.",
        ),
        "_allowlist_function_transition": _ALLOWLIST,
    },
    test = True,
)

# Runs the test built for Mac Catalyst from the runfiles root, as Bazel runs any test. A Catalyst
# executable runs natively on the Mac: dyld finds UIKit and the iOS SwiftUI in /System/iOSSupport.
_RUNNER = """#!/bin/sh
exec "./{test}" "$@"
"""

def _catalyst_test_impl(ctx):
    test = ctx.attr.test[0]
    executable = test[DefaultInfo].files_to_run.executable
    runner = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.write(runner, _RUNNER.format(test = executable.short_path), is_executable = True)
    providers = [
        DefaultInfo(
            executable = runner,
            runfiles = ctx.runfiles(files = [executable]).merge(test[DefaultInfo].default_runfiles),
        ),
        coverage_common.instrumented_files_info(ctx, dependency_attributes = ["test"]),
    ]

    # The Xcode environment and `requires-darwin`: without them the test binary can't find XCTest
    # ("Bazel must set the SDKROOT in order to find XCTest").
    if RunEnvironmentInfo in test:
        providers.append(test[RunEnvironmentInfo])
    if testing.ExecutionInfo in test:
        providers.append(test[testing.ExecutionInfo])
    return providers

catalyst_test = rule(
    implementation = _catalyst_test_impl,
    doc = "Builds `test`, a Swift test target, for Mac Catalyst and runs it on the Mac.",
    attrs = {
        "minimum_os_version": attr.string(
            mandatory = True,
            doc = "The iOS version the Catalyst target triple names (`17.0`).",
        ),
        "test": attr.label(
            cfg = _catalyst_transition,
            executable = True,
            mandatory = True,
            doc = "The test to build for Mac Catalyst: a `swift_test` (tools/swift_rules.bzl), with its dependencies.",
        ),
        "_allowlist_function_transition": _ALLOWLIST,
    },
    test = True,
)
