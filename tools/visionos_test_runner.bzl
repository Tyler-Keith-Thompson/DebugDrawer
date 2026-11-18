"""`visionos_test_runner`: runs a `visionos_unit_test` bundle in a visionOS simulator.

rules_apple's own visionOS runner exits 1 without running anything: its xctestrunner hardcodes iOS
devices and runtimes, and its xctestrun runner hardcodes the iPhoneSimulator platform. This one does
for visionOS what that runner does for an iOS test with no test host: it creates a simulator on the
newest visionOS runtime installed, boots it, runs the bundle under the XRSimulator platform's
`xctest` agent with `simctl spawn`, and deletes the simulator. A fresh simulator per run keeps
concurrent runs (several worktrees, say) from sharing one, and from sharing its UserDefaults.
"""

load("@rules_apple//apple:providers.bzl", "apple_provider")

def _visionos_test_runner_impl(ctx):
    runner = ctx.actions.declare_file(ctx.label.name + ".sh")
    ctx.actions.expand_template(
        template = ctx.file._template,
        output = runner,
        substitutions = {"%(device_type)s": ctx.attr.device_type},
    )
    return [
        apple_provider.make_apple_test_runner_info(
            test_runner_template = runner,
            execution_requirements = {"requires-darwin": ""},
            execution_environment = {},
        ),
        DefaultInfo(),
    ]

visionos_test_runner = rule(
    implementation = _visionos_test_runner_impl,
    attrs = {
        "device_type": attr.string(
            default = "",
            doc = "A simulator device type identifier; empty picks the first the runtime supports.",
        ),
        "_template": attr.label(
            default = ":visionos_test_runner.template.sh",
            allow_single_file = True,
        ),
    },
    doc = "A test runner for visionos_unit_test that runs the bundle in a new visionOS simulator.",
)
