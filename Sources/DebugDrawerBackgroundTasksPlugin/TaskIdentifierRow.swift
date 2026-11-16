#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// A row named by a task identifier: a glyph or symbol, the identifier in the drawer's code
    /// type, details below it and an accessory at the trailing edge.
    ///
    /// The plugin lays this row out itself rather than use `DebugDrawerIssueRow`, whose title is
    /// set in the system font: an identifier is code (`DebugDrawerCodeText`). It keeps to one line
    /// cut in the middle, so both its ends show (reverse-DNS identifiers differ at the end), until
    /// tapped; its tooltip and VoiceOver have it whole. At accessibility text sizes the glyph sits
    /// above the identifier, so the text has the row's width.
    struct TaskIdentifierRow<Glyph: View, Details: View, Accessory: View>: View {
        let identifier: String
        let glyph: Glyph
        let details: Details
        let accessory: Accessory
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        /// The glyph's column, so identifiers line up whatever symbol leads them.
        @ScaledMetric(relativeTo: .body) private var glyphWidth: CGFloat = Self.defaultGlyphWidth

        #if os(macOS)
            private static var defaultGlyphWidth: CGFloat {
                18
            }
        #else
            private static var defaultGlyphWidth: CGFloat {
                24
            }
        #endif

        init(
            _ identifier: String,
            @ViewBuilder glyph: () -> Glyph,
            @ViewBuilder details: () -> Details,
            @ViewBuilder accessory: () -> Accessory
        ) {
            self.identifier = identifier
            self.glyph = glyph()
            self.details = details()
            self.accessory = accessory()
        }

        var body: some View {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
            layout {
                glyph
                    .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : glyphWidth)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        // One line cut in the middle until tapped, at every text size: wrapped,
                        // SwiftUI hyphenates inside the identifier's words, adding hyphens that
                        // aren't in it.
                        DebugDrawerCodeText(identifier)
                            .debugDrawerForegroundStyle(.primary)
                        accessory
                    }
                    details
                        .debugDrawerFont(.secondary)
                        .debugDrawerForegroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .debugDrawerRowPadding()
        }
    }

    extension TaskIdentifierRow where Accessory == EmptyView {
        /// A row with no accessory.
        init(_ identifier: String, @ViewBuilder glyph: () -> Glyph, @ViewBuilder details: () -> Details) {
            self.init(identifier, glyph: glyph, details: details) { EmptyView() }
        }
    }
#endif
