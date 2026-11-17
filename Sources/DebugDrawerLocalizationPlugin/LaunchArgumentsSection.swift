#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// Apple's launch arguments for testing localization, each to copy into a scheme: they apply
    /// to every string from launch, SwiftUI's and the system's included.
    struct LaunchArgumentsSection: View {
        /// The language `-AppleLanguages` runs the app in, or `nil` for none to offer.
        let language: String?

        var body: some View {
            DebugDrawerSection("Launch Arguments") {
                ForEach(LaunchArgument.all(language: language), id: \.argument) { launchArgument in
                    DebugDrawerRow(launchArgument.title) {
                        DebugDrawerCodeText(launchArgument.argument)
                    } accessory: {
                        DebugDrawerCopyButton("Copy") { launchArgument.argument }
                            .accessibilityLabel("Copy \(launchArgument.argument)")
                    }
                }
            } footer: {
                Text(
                    "Add one to the scheme's Arguments Passed On Launch. "
                        + "Each changes every string from launch, the system's and the drawer's included."
                )
            }
        }
    }

    /// One of Apple's launch arguments, and what it does.
    struct LaunchArgument: Hashable, Sendable {
        let title: String
        let argument: String

        /// Foundation's own pseudo-languages and direction, and the app run in `language`.
        static func all(language: String?) -> [LaunchArgument] {
            [
                LaunchArgument(title: "Double-Length Strings", argument: "-NSDoubleLocalizedStrings YES"),
                LaunchArgument(title: "Accented Strings", argument: "-NSAccentuateLocalizedStrings YES"),
                LaunchArgument(title: "Untranslated in Capitals", argument: "-NSShowNonLocalizedStrings YES"),
                LaunchArgument(title: "Right-to-Left", argument: "-NSForceRightToLeftWritingDirection YES")
            ] + (language.map { [LaunchArgument(title: "Run in \($0)", argument: "-AppleLanguages (\($0))")] } ?? [])
        }
    }
#endif
