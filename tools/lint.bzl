LintInfo = provider(fields = ["outputs"])

def _swiftlint(ctx, target, srcs):
    configs = [ctx.file._swiftlint_config]
    if ctx.rule.attr.testonly:
        configs.append(ctx.file._swiftlint_tests_config)
    output = ctx.actions.declare_file(target.label.name + ".swiftlint")
    args = ctx.actions.args()
    args.add_all(["lint", "--strict", "--quiet", "--no-cache"])
    args.add_all(configs, before_each = "--config")
    args.add_all(srcs)
    ctx.actions.run_shell(
        command = '"$1" "${@:2}" && touch "%s"' % output.path,
        arguments = [ctx.executable._swiftlint.path, args],
        inputs = srcs + configs,
        tools = [ctx.executable._swiftlint],
        outputs = [output],
        mnemonic = "SwiftLint",
        progress_message = "Linting %{label} with SwiftLint",
    )
    return output

def _a11y_check(ctx, target, srcs):
    output = ctx.actions.declare_file(target.label.name + ".a11y-check")
    args = ctx.actions.args()
    args.add_all(["--no-trend", "--format", "xcode"])
    args.add_all(srcs)
    ctx.actions.run_shell(
        command = 'report=$("$1" "${@:2}") || { echo "$report"; exit 1; }; touch "%s"' % output.path,
        arguments = [ctx.executable._a11y_check.path, args],
        inputs = srcs,
        tools = [ctx.executable._a11y_check],
        outputs = [output],
        mnemonic = "A11yCheck",
        progress_message = "Checking accessibility of %{label}",
    )
    return output

def _lint_aspect_impl(target, ctx):
    if target.label.workspace_name:
        return [LintInfo(outputs = depset())]
    transitive = [dep[LintInfo].outputs for dep in getattr(ctx.rule.attr, "deps", []) if LintInfo in dep]
    direct = []
    if ctx.rule.kind == "swift_library":
        srcs = [src for src in ctx.rule.files.srcs if src.extension == "swift" and src.is_source]
        direct.append(_swiftlint(ctx, target, srcs))
        if not ctx.rule.attr.testonly:
            direct.append(_a11y_check(ctx, target, srcs))
    outputs = depset(direct, transitive = transitive)
    return [LintInfo(outputs = outputs), OutputGroupInfo(lint = outputs)]

lint_aspect = aspect(
    implementation = _lint_aspect_impl,
    attr_aspects = ["deps"],
    attrs = {
        "_a11y_check": attr.label(default = "@a11y_check//:a11y-check", executable = True, cfg = "exec"),
        "_swiftlint": attr.label(default = "@SwiftLint//:swiftlint", executable = True, cfg = "exec"),
        "_swiftlint_config": attr.label(default = "//:.swiftlint.yml", allow_single_file = True),
        "_swiftlint_tests_config": attr.label(default = "//:.swiftlint-tests.yml", allow_single_file = True),
    },
)
