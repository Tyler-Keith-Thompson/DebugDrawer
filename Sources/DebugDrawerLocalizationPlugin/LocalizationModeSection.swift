#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// Pseudo-Localize and Show Keys, one at a time, with a sample of what pseudo-localization
    /// draws and where the modes apply.
    struct LocalizationModeSection: View {
        @Binding var mode: Localization.Mode

        var body: some View {
            DebugDrawerSection("Mode") {
                DebugDrawerRow("Pseudo-Localize", systemImage: "textformat", isOn: isOn(.pseudoLocalized))
                    .accessibilityHint("Accents the app's strings and makes them about 40% longer")
                if mode == .pseudoLocalized {
                    DebugDrawerKeyValueRow("Settings", value: PseudoLocalization.transform("Settings"))
                }
                DebugDrawerRow("Show Keys", systemImage: "key", isOn: isOn(.showingKeys))
                    .accessibilityHint("Shows each string's localization key in its place")
            } footer: {
                Text("Live, for the app's NSLocalizedString and Bundle strings. SwiftUI's Text needs Whole App on Next Launch.")
            }
        }

        /// On while the mode is `onMode`; turning it on picks that mode, turning it off the
        /// translations.
        private func isOn(_ onMode: Localization.Mode) -> Binding<Bool> {
            Binding(get: { mode == onMode }, set: { mode = $0 ? onMode : .standard })
        }
    }
#endif
