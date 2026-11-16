import SwiftUI

/// A frame of a stack trace, as Xcode's debug navigator shows one: its index, a badge saying whose
/// code it is (the app's own, in the accent color with a person, or the system's, in gray), the
/// symbol, and the binary it's in below.
///
/// The symbol is code, so it is monospaced; it keeps to two lines cut in the middle, so both its
/// ends show, until the row is tapped or selected, which shows it whole. VoiceOver always reads it
/// whole. The app's own symbols are semibold; the system's are in the secondary color, so the
/// app's frames stand out. Mark the first of the app's frames `isSelected`: it is drawn as Xcode draws
/// the selected frame, in white on the selection color, so the eye lands on it first. While the
/// drawer's "Show only my code" filter is on (`EnvironmentValues.debugDrawerShowsOnlyOwnCode`),
/// the system's frames draw nothing.
///
/// ```swift
/// ForEach(frames) { frame in
///     DebugDrawerStackFrameRow(index: frame.index, symbol: frame.symbol, image: frame.image,
///                              isOwnCode: frame.isApp, isSelected: frame.id == firstAppFrame?.id)
/// }
/// ```
///
/// The type exists in every build so a plugin's body compiles unchanged in release, where it
/// draws nothing.
public struct DebugDrawerStackFrameRow: View {
    let index: Int
    let symbol: String
    let image: String
    let isOwnCode: Bool
    let isSelected: Bool

    /// - Parameters:
    ///   - index: The frame's place in the stack, 0 for the innermost.
    ///   - symbol: The function ("OrdersViewModel.load()").
    ///   - image: The binary the frame is in ("Example", "libswiftCore.dylib").
    ///   - isOwnCode: Whether the binary is the app's own.
    ///   - isSelected: Whether to draw the frame selected: the first of the app's frames.
    public init(index: Int, symbol: String, image: String, isOwnCode: Bool, isSelected: Bool = false) {
        self.index = index
        self.symbol = symbol
        self.image = image
        self.isOwnCode = isOwnCode
        self.isSelected = isSelected
    }

    public var body: some View {
        #if DEBUG
            DrawerStackFrameRowLayout(row: self)
        #else
            EmptyView()
        #endif
    }
}

public extension EnvironmentValues {
    /// Whether the drawer's "Show only my code" filter is on: stack traces leave out the system's
    /// frames. ``DebugDrawerStackFrameRow`` reads it; a plugin that lists frames its own way can
    /// too.
    @Entry var debugDrawerShowsOnlyOwnCode = false
}

#if DEBUG
    extension DebugDrawerStackFrameRow {
        /// What VoiceOver reads for the frame ("Frame 2, OrdersViewModel.load(), in Example, the
        /// app's code").
        var spokenLabel: String {
            "Frame \(index), \(symbol), in \(image)\(isOwnCode ? ", the app's code" : "")"
        }
    }

    /// The stack frame row's face.
    struct DrawerStackFrameRowLayout: View {
        let row: DebugDrawerStackFrameRow
        @Environment(\.debugDrawerShowsOnlyOwnCode) private var showsOnlyOwnCode
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @ScaledMetric(relativeTo: .body) private var badge = DrawerSpacing.glyph
        @ScaledMetric(relativeTo: .body) private var indexWidth = DrawerSpacing.glyph * 1.2
        @ScaledMetric(relativeTo: .body) private var padding = DrawerSpacing.rowPadding
        @ScaledMetric(relativeTo: .body) private var gap = DrawerSpacing.itemGap
        @State private var isExpanded = false

        var body: some View {
            if row.isOwnCode || !showsOnlyOwnCode {
                // At accessibility sizes the index and badge sit above the symbol, so the symbol
                // has the row's width.
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: gap))
                layout {
                    HStack(alignment: .firstTextBaseline, spacing: gap) {
                        Text(row.index, format: .number)
                            .debugDrawerFont(.code)
                            .foregroundStyle(row.isSelected ? DrawerPalette.onSelection.opacity(0.78) : DrawerPalette.tertiaryText)
                            .frame(minWidth: indexWidth, alignment: .trailing)
                        badgeView
                            .alignmentGuide(.firstTextBaseline) { $0[.bottom] - $0.height * 0.15 }
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(row.symbol)
                            .debugDrawerFont(.code)
                            .fontWeight(row.isOwnCode ? .semibold : .regular)
                            .foregroundStyle(symbolColor)
                            .lineLimit(showsWholeSymbol ? nil : 2)
                            .truncationMode(.middle)
                            .fixedSize(horizontal: false, vertical: true)
                            .help(row.symbol)
                        Text(row.image)
                            .debugDrawerFont(.secondary)
                            .foregroundStyle(row.isSelected ? DrawerPalette.onSelection.opacity(0.78) : DrawerPalette.tertiaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, padding)
                .padding(.horizontal, padding)
                .background {
                    if row.isSelected {
                        RoundedRectangle(cornerRadius: DrawerSpacing.badgeRadius).fill(DrawerPalette.selection)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { isExpanded.toggle() }
                .debugDrawerTextSelection()
                .accessibilityElement(children: .combine)
                .accessibilityLabel(row.spokenLabel)
                // VoiceOver reads the symbol whole either way; the tap changes only what is drawn.
                .accessibilityAddTraits(.isButton)
                .accessibilityHint(showsWholeSymbol ? "Shows the symbol on two lines" : "Shows the whole symbol")
            }
        }

        /// The selected frame, the one the eye lands on, shows its symbol whole; another does once
        /// tapped.
        private var showsWholeSymbol: Bool {
            row.isSelected || isExpanded
        }

        private var symbolColor: Color {
            if row.isSelected { return DrawerPalette.onSelection }
            return row.isOwnCode ? DrawerPalette.text : DrawerPalette.secondaryText
        }

        private var badgeView: some View {
            let shape = RoundedRectangle(cornerRadius: DrawerSpacing.badgeRadius)
            let fill: Color = row.isSelected
                ? .white.opacity(0.25)
                : (row.isOwnCode ? DrawerPalette.accent : DrawerPalette.systemGray)
            return Image(systemName: row.isOwnCode ? "person.fill" : "gearshape.fill")
                .resizable()
                .scaledToFit()
                .padding(badge * 0.2)
                .foregroundStyle(.white)
                .frame(width: badge, height: badge)
                .background(fill, in: shape)
                .accessibilityHidden(true)
        }
    }
#endif
