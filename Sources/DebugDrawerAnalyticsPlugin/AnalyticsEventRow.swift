#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// One event in the list: its name, the time it was recorded and what it carries. Selected, it
    /// is drawn on the selection fill, and its properties and JSON show below the list
    /// (``AnalyticsEventDetail``).
    struct AnalyticsEventRow: View {
        let event: AnalyticsEvent
        let isSelected: Bool
        let onToggle: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @Environment(\.locale) private var locale
        @Environment(\.timeZone) private var timeZone

        var body: some View {
            Button(action: onToggle) {
                summary
            }
            .debugDrawerButtonStyle(.plain)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityHint(isSelected ? "Hides the properties" : "Shows the properties below the list")
        }

        // The name keeps to one line cut in the middle, so both ends of a long snake-case name
        // show; wrapped, SwiftUI would break and hyphenate inside it. Selected, it shows whole, as
        // Keychain's selected item does, free to break after its separators rather than inside a
        // word. At accessibility text sizes the time leaves the name too little width, so it sits
        // below.
        private var summary: some View {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            return VStack(alignment: .leading, spacing: 2) {
                layout {
                    Text(isSelected ? event.name.breakableAtSeparators : event.name)
                        .debugDrawerFont(.body)
                        .debugDrawerForegroundStyle(.primary)
                        .lineLimit(isSelected ? nil : 1)
                        .truncationMode(.middle)
                        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? nil : .infinity, alignment: .leading)
                        .help(event.name)
                    Text(event.time(locale: locale, timeZone: timeZone))
                        .debugDrawerFont(.value)
                        .debugDrawerForegroundStyle(.tertiary)
                }
                Text(event.summary)
                    .debugDrawerFont(.secondary)
                    .debugDrawerForegroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .debugDrawerRowPadding()
            .debugDrawerSelected(isSelected)
            .contentShape(Rectangle())
        }
    }

    extension AnalyticsEvent {
        /// The time of day it was recorded, to the millisecond, in `locale` and `timeZone`: events
        /// sent together tell apart.
        func time(locale: Locale, timeZone: TimeZone) -> String {
            timestamp.formatted(
                Date.FormatStyle(locale: locale, timeZone: timeZone).hour().minute().second().secondFraction(.fractional(3))
            )
        }
    }
#endif
