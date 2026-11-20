"""`simulator_test_runner`: runs a visionOS, tvOS or watchOS unit test bundle in a new simulator.

rules_apple's own runners for these platforms exit without running anything: its xctestrunner
hardcodes iOS devices and runtimes, and its xctestrun runner hardcodes the iPhoneSimulator
platform. This one does for each platform what that runner does for an iOS test with no test host:
it creates a simulator on the newest runtime of the platform installed, boots it, runs the bundle
under the platform simulator's `xctest` agent with `simctl spawn`, and deletes the simulator. A
fresh simulator per run keeps concurrent runs (several worktrees, say) from sharing one, and from
sharing its UserDefaults.
"""

load("@rules_apple//apple:providers.bzl", "apple_provider")

def _simulator_test_runner_impl(ctx):
    runner = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.expand_template(
        template = ctx.file._template,
        output = runner,
        substitutions = {
            "%(device_type)s": ctx.attr.device_type,
            "%(platform_name)s": ctx.attr.platform_name,
            "%(runtime_platform)s": ctx.attr.runtime_platform,
            "%(simulator_platform)s": ctx.attr.simulator_platform,
        },
    )
    return [
        apple_provider.make_apple_test_runner_info(
            test_runner_template = runner,
            execution_requirements = {"requires-darwin": ""},
            execution_environment = {},
        ),
        DefaultInfo(),
    ]

simulator_test_runner = rule(
    implementation = _simulator_test_runner_impl,
    attrs = {
        "device_type": attr.string(
            default = "",
            doc = "A simulator device type identifier; empty picks the first the runtime supports.",
        ),
        "platform_name": attr.string(
            mandatory = True,
            doc = "The platform's name in messages (`visionOS`).",
        ),
        "runtime_platform": attr.string(
            mandatory = True,
            doc = "The platform `simctl list runtimes --json` names the runtime with (`xrOS`).",
        ),
        "simulator_platform": attr.string(
            mandatory = True,
            doc = "The simulator platform's directory under Xcode's Platforms, less `.platform` (`XRSimulator`).",
        ),
        "_template": attr.label(
            default = ":simulator_test_runner.template.sh",
            allow_single_file = True,
        ),
    },
    doc = "A test runner for visionos_unit_test, tvos_unit_test and watchos_unit_test that runs the bundle in a new simulator.",
)
