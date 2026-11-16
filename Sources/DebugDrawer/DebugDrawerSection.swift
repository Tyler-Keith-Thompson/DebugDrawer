import SwiftUI

/// A group of rows inside a plugin: an optional heading in sentence case, the rows, and an
/// optional note below them.
///
/// A section adds no box or rule of its own: the drawer's panel is one surface, and the hairline
/// under each plugin is the only division. Rows (``DebugDrawerRow``, ``DebugDrawerKeyValueRow``
/// and the others) pad themselves, so they and sections stack with no spacing; end the plugin's
/// body with a ``DebugDrawerActionRow`` for its actions.
///
/// ```swift
/// DebugDrawerSection("Build") {
///     DebugDrawerKeyValueRow("Version", value: "1.4.2 (88)")
///     DebugDrawerKeyValueRow("Bundle ID", value: "com.example.orders")
/// } footer: {
///     Text("Read from the main bundle's Info.plist.")
/// }
/// ```
///
/// The type exists in every build so a plugin's body compiles unchanged in release, where it
/// draws nothing.
public struct DebugDrawerSection<Content: View, Footer: View>: View {
    let title: String?
    let content: Content
    let footer: Footer

    /// - Parameters:
    ///   - title: The section's name, shown above the rows and read by VoiceOver as a
    ///     heading; `nil` for none.
    ///   - content: The rows.
    ///   - footer: A note below the rows, in the drawer's secondary text.
    public init(_ title: String? = nil, @ViewBuilder content: () -> Content, @ViewBuilder footer: () -> Footer) {
        self.title = title
        self.content = content()
        self.footer = footer()
    }

    public var body: some View {
        #if DEBUG
            DrawerSectionLayout(title: title, content: content, footer: footer)
        #else
            EmptyView()
        #endif
    }
}

public extension DebugDrawerSection where Footer == EmptyView {
    /// A section with no footer.
    ///
    /// - Parameters:
    ///   - title: The section's name, shown above the rows; `nil` for none.
    ///   - content: The rows.
    init(_ title: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title, content: content) { EmptyView() }
    }
}

#if DEBUG
    /// The section's face: the heading, the rows and the note.
    struct DrawerSectionLayout<Content: View, Footer: View>: View {
        let title: String?
        let content: Content
        let footer: Footer
        @ScaledMetric(relativeTo: .body) private var padding = DrawerSpacing.rowPadding

        var body: some View {
            VStack(alignment: .leading, spacing: 0) {
                if let title {
                    DrawerHeadingText(title)
                        .padding(.top, padding * 2)
                        .padding(.bottom, padding / 2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                content
                if Footer.self != EmptyView.self {
                    footer
                        .debugDrawerFont(.secondary)
                        .foregroundStyle(DrawerPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.bottom, padding)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
#endif
