#if DEBUG
    import SwiftUI

    /// A choice made from a menu, its current option as the label: the Mac's pop-up button, and
    /// elsewhere a menu whose label SwiftUI draws.
    ///
    /// UIKit's menu button keeps one line's height, so at accessibility text sizes a long option
    /// wrapped over the row below it; a label SwiftUI draws grows with its text.
    struct MenuPicker<Value: Hashable, Options: View>: View {
        let title: String
        @Binding var selection: Value
        /// The name of the option chosen, which labels the menu outside the Mac.
        let current: String
        let options: Options
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        /// - Parameters:
        ///   - title: What is chosen, which VoiceOver reads.
        ///   - selection: The option chosen.
        ///   - current: Its name.
        ///   - options: Each option, tagged with its value.
        init(_ title: String, selection: Binding<Value>, current: String, @ViewBuilder options: () -> Options) {
            self.title = title
            _selection = selection
            self.current = current
            self.options = options()
        }

        var body: some View {
            #if os(macOS)
                Picker(title, selection: $selection) { options }
                    .pickerStyle(.menu)
                    .fixedSize()
                    .accessibilityLabel(title)
            #else
                Menu {
                    Picker(title, selection: $selection) { options }
                        .accessibilityLabel(title)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(current)
                            .multilineTextAlignment(.leading)
                        Image(systemName: "chevron.up.chevron.down")
                            .imageScale(.small)
                            .accessibilityHidden(true)
                    }
                }
                // One line beside the row's title; below it, at accessibility sizes, as wide as the row.
                .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
                .accessibilityLabel(title)
                .accessibilityValue(current)
            #endif
        }
    }
#endif
