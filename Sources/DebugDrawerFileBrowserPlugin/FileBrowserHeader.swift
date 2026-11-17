#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// What the browser shows, at its top: a back button, then the folder's or file's name and
    /// its path from its root, cut in the middle.
    struct FileBrowserHeader: View {
        let title: String
        /// The path from the root: "Documents/Exports/report.json".
        let path: String
        /// Where Back goes, for VoiceOver: "Locations", or the folder above.
        let backTitle: String
        let onBack: () -> Void
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Button(action: onBack) {
                    Label("Back", systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                }
                .debugDrawerButtonStyle(.borderless)
                .accessibilityLabel("Back to \(backTitle)")
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .debugDrawerFont(.heading)
                        .debugDrawerForegroundStyle(.primary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .truncationMode(.middle)
                        .accessibilityAddTraits(.isHeader)
                    Text(path)
                        .debugDrawerFont(.code)
                        .debugDrawerForegroundStyle(.tertiary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .truncationMode(.middle)
                        .help(path)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .debugDrawerRowPadding()
        }
    }
#endif
