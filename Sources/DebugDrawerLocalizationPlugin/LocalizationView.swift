#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The plugin's body: the live mode, the next launch's settings, the translations missing
    /// for a language (the current one unless another is picked), and Apple's launch arguments.
    /// It keeps which language is picked and the filter.
    struct LocalizationView: View {
        @Binding var mode: Localization.Mode
        let bundles: [LocalizedBundle]
        let lookups: [LocalizationLookup]
        /// Foundation's settings stored for the next launch, and those the app launched with.
        var nextLaunch: Set<NextLaunchOption> = []
        var launchedWith: Set<NextLaunchOption> = []
        var onNextLaunchChange: (NextLaunchOption, Bool) -> Void = { _, _ in }
        let onRefresh: () -> Void
        /// The language picked, or `nil` for the one the app runs in.
        @State private var picked: String?
        @State private var query = ""
        let inspection = Inspection<Self>()

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                LocalizationModeSection(mode: $mode)
                NextLaunchSection(stored: nextLaunch, launchedWith: launchedWith, onChange: onNextLaunchChange)
                MissingTranslationsSection(
                    language: $picked.or(bundles.currentLocalization ?? bundles.developmentLocalization ?? ""),
                    query: $query,
                    bundles: bundles,
                    lookups: lookups,
                    onRefresh: onRefresh
                )
                LaunchArgumentsSection(language: picked ?? bundles.currentLocalization)
            }
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
        }
    }

    extension Binding where Value == String? {
        /// The value, or `fallback` while it is `nil`; setting it sets the value.
        fileprivate func or(_ fallback: String) -> Binding<String> {
            Binding<String>(get: { wrappedValue ?? fallback }, set: { wrappedValue = $0 })
        }
    }
#endif
