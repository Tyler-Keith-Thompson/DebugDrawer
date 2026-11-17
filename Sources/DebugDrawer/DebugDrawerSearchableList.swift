import SwiftUI

/// A filter field above a scrolling list of rows on a dark panel, for a plugin that lists many
/// items. The plugin owns the filter: it binds the field's text and passes the rows that match.
///
/// The rows stack with no spacing and are built lazily as they scroll into view; give each row its
/// own divider.
///
/// The type exists in every build so a plugin's body compiles unchanged in release, where it
/// draws nothing.
public struct DebugDrawerSearchableList<Content: View>: View {
    let prompt: String
    let text: Binding<String>
    let fieldLabel: String
    let maxHeight: CGFloat
    let content: Content

    /// A filter field above a list of `content` that scrolls past `maxHeight`.
    ///
    /// - Parameters:
    ///   - prompt: The field's placeholder ("Filter...").
    ///   - text: The filter text.
    ///   - accessibilityLabel: What the field filters by, for VoiceOver ("Filter keys and values").
    ///   - maxHeight: The tallest the list grows before it scrolls, in points.
    ///   - content: The rows to list.
    public init(
        _ prompt: String,
        text: Binding<String>,
        accessibilityLabel: String,
        maxHeight: CGFloat = 250,
        @ViewBuilder content: () -> Content
    ) {
        self.prompt = prompt
        self.text = text
        fieldLabel = accessibilityLabel
        self.maxHeight = maxHeight
        self.content = content()
    }

    public var body: some View {
        #if DEBUG
            list
        #else
            EmptyView()
        #endif
    }
}

#if DEBUG
    extension DebugDrawerSearchableList {
        private var list: some View {
            VStack(alignment: .leading, spacing: 6) {
                TextField(prompt, text: text)
                    .debugDrawerTextFieldStyle()
                    .accessibilityLabel(fieldLabel)

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        content
                    }
                    .padding(.horizontal, DrawerSpacing.itemGap)
                }
                .frame(maxHeight: maxHeight)
                .drawerWell()
            }
        }
    }

    extension View {
        /// Sets the view into the panel as a well with a hairline edge, as a code block is.
        fileprivate func drawerWell() -> some View {
            modifier(DrawerWell())
        }
    }

    /// The look `drawerWell()` gives a scrolling list.
    private struct DrawerWell: ViewModifier {
        @Environment(\.displayScale) private var displayScale

        func body(content: Content) -> some View {
            let shape = RoundedRectangle(cornerRadius: DrawerSpacing.codeRadius)
            content
                .background(DrawerPalette.well, in: shape)
                .clipShape(shape)
                .overlay { shape.strokeBorder(DrawerPalette.separator, lineWidth: 1 / displayScale) }
        }
    }
#endif
