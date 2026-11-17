#if DEBUG
    import DebugDrawer
    import SwiftUI

    // Rather than a menu-style Picker: on iOS that picker's label wraps a long identifier
    // ("TEAMID.com.example.shared") over lines, hyphenated, and at accessibility text sizes is
    // clipped by the row below; its label can't be told how many lines to take.
    /// A menu of choices whose button shows the chosen one on a single line, cut in the middle, and
    /// in full at accessibility text sizes.
    struct KeychainChoiceMenu<Choice: Hashable>: View {
        let title: String
        @Binding var selection: Choice
        let choices: [Choice]
        /// The words a choice is shown as.
        let label: (Choice) -> String

        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            Menu {
                Picker(title, selection: $selection) {
                    ForEach(choices, id: \.self) { Text(label($0)).tag($0) }
                }
                .pickerStyle(.inline)
                .accessibilityLabel(title)
            } label: {
                HStack(spacing: 4) {
                    Text(label(selection))
                        .debugDrawerFont(.code)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                        .truncationMode(.middle)
                    Image(systemName: "chevron.up.chevron.down")
                        .debugDrawerFont(.secondary)
                        .accessibilityHidden(true)
                }
            }
            .menuStyle(.button)
            .debugDrawerButtonStyle(.secondary)
            .accessibilityLabel(title)
            .accessibilityValue(label(selection))
        }
    }
#endif
