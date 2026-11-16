import SwiftUI

/// A block of code, a log or a stack: its lines set into the panel in a well with a hairline
/// edge, in the drawer's monospaced code type, selectable.
///
/// ```swift
/// DebugDrawerCodeBlock {
///     Text(payloadJSON)
/// }
/// ```
///
/// The type exists in every build so a plugin's body compiles unchanged in release, where it
/// draws nothing.
public struct DebugDrawerCodeBlock<Content: View>: View {
    let content: Content

    /// - Parameter content: The lines.
    public init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    public var body: some View {
        #if DEBUG
            DrawerCodeBlockSurface(content: content)
        #else
            EmptyView()
        #endif
    }
}

#if DEBUG
    /// The code block's face.
    struct DrawerCodeBlockSurface<Content: View>: View {
        let content: Content
        @ScaledMetric(relativeTo: .footnote) private var padding = DrawerSpacing.codePadding
        @ScaledMetric(relativeTo: .footnote) private var radius = DrawerSpacing.codeRadius
        @Environment(\.displayScale) private var displayScale

        var body: some View {
            let shape = RoundedRectangle(cornerRadius: radius)
            VStack(alignment: .leading, spacing: 2) {
                content
            }
            .debugDrawerFont(.code)
            .foregroundStyle(DrawerPalette.text)
            .debugDrawerTextSelection()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DrawerPalette.well, in: shape)
            .overlay { shape.strokeBorder(DrawerPalette.separator, lineWidth: 1 / displayScale) }
        }
    }
#endif
