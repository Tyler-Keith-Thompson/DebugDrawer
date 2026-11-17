import SwiftUI

/// A plugin's actions, in the same place in every plugin: a row of push buttons under the
/// content, the everyday actions at the leading edge and a destructive one pushed to the trailing
/// edge, apart from them. Buttons that don't fit on one line wrap to the next; at accessibility
/// text sizes they stack.
///
/// Its buttons take ``DebugDrawerButtonStyle/secondary`` unless they name another style; one at
/// most may be ``DebugDrawerButtonStyle/primary``. Put it last in the plugin's body, or in a
/// row's details for actions on that row alone.
///
/// ```swift
/// DebugDrawerActionRow {
///     DebugDrawerCopyButton("Copy Info") { info }
///     Button("Refresh", action: refresh)
/// } trailing: {
///     Button("Delete All", role: .destructive, action: deleteAll)
///         .debugDrawerButtonStyle(.destructive)
/// }
/// ```
///
/// The type exists in every build so a plugin's body compiles unchanged in release, where it
/// draws nothing.
public struct DebugDrawerActionRow<Leading: View, Trailing: View>: View {
    let leading: Leading
    let trailing: Trailing

    /// An action row with everyday actions and one kept apart at the trailing edge.
    ///
    /// - Parameters:
    ///   - leading: The everyday actions, in reading order.
    ///   - trailing: An action kept apart at the trailing edge, typically a destructive one.
    public init(@ViewBuilder leading: () -> Leading, @ViewBuilder trailing: () -> Trailing) {
        self.leading = leading()
        self.trailing = trailing()
    }

    public var body: some View {
        #if DEBUG
            DrawerActionRowLayout(leading: leading, trailing: trailing)
        #else
            EmptyView()
        #endif
    }
}

public extension DebugDrawerActionRow where Trailing == EmptyView {
    /// An action row with no action kept apart.
    ///
    /// - Parameter leading: The actions, in reading order.
    init(@ViewBuilder leading: () -> Leading) {
        self.init(leading: leading) { EmptyView() }
    }
}

#if DEBUG
    /// The action row's face: the buttons in lines that wrap, or a column at accessibility sizes.
    struct DrawerActionRowLayout<Leading: View, Trailing: View>: View {
        let leading: Leading
        let trailing: Trailing
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @Environment(\.isInDrawerRow) private var isInRow
        @ScaledMetric(relativeTo: .body) private var gap = DrawerSpacing.actionGap
        @ScaledMetric(relativeTo: .body) private var padding = DrawerSpacing.rowPadding

        var body: some View {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: gap) {
                        leading
                        trailing
                    }
                    // Its ideal height: squeezed, the buttons' wrapped titles would spill over
                    // the button below.
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(alignment: .top, spacing: gap) {
                        DrawerWrappingLayout(spacing: gap) { leading }
                        if Trailing.self != EmptyView.self {
                            Spacer(minLength: gap)
                            trailing
                        }
                    }
                }
            }
            .debugDrawerButtonStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, isInRow ? padding : padding * 2)
            .padding(.bottom, isInRow ? 0 : padding * 2)
        }
    }
#endif
