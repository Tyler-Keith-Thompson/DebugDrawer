"""`catalyst_build_test`: compiles Swift libraries for Mac Catalyst.

Bazel and rules_apple have no Mac Catalyst platform: rules_apple has no Catalyst rules, apple_support
registers no Catalyst CPU, and `--apple_platform_type=catalyst --catalyst_cpus=arm64` crashes
Bazel's analysis ("No supported apple platform registered for target cpu catalyst_arm64"). A
Catalyst build is a macOS build with an iOS target triple, though: the macOS SDK, the
`<arch>-apple-ios<version>-macabi` target and the SDK's iOSSupport frameworks. So this rule
builds its targets in the macOS configuration with rules_swift's `copt` flag set to that target,
and swiftc compiles them as Catalyst code, where `os(iOS)` and `targetEnvironment(macCatalyst)`
hold. It compiles and archives; it links no app, so it checks Swift libraries with no C or
Objective-C dependencies (those would still build for macOS).
"""

_COPT = "@rules_swift//swift:copt"

def _catalyst_transition_impl(settings, attr):
    cpu = settings["//command_line_option:cpu"]
    if not cpu.startswith("darwin_"):
        fail("catalyst_build_test builds on a Mac only; the target CPU is {}".format(cpu))
    arch = cpu.removeprefix("darwin_")
    return {_COPT: settings[_COPT] + [
        "-target",
        "{}-apple-ios{}-macabi".format(arch, attr.minimum_os_version),
        # UIKit and the iOS flavor of SwiftUI live in the macOS SDK's iOSSupport tree; swiftc
        # finds the iOSSupport library paths from the target, but not its frameworks.
        "-Fsystem",
        "__BAZEL_XCODE_SDKROOT__/System/iOSSupport/System/Library/Frameworks",
    ]}

_catalyst_transition = transition(
    implementation = _catalyst_transition_impl,
    inputs = ["//command_line_option:cpu", _COPT],
    outputs = [_COPT],
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
        "_allowlist_function_transition": attr.label(
            default = "@bazel_tools//tools/allowlists/function_transition_allowlist",
        ),
    },
    test = True,
)
