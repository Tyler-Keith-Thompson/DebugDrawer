import SwiftUI

/// A row in a ``DebugDrawerSection``: an optional icon, a title, details below it and an
/// accessory at the trailing edge, such as a status, a toggle or a picker.
///
/// The icon sits in a column of its own, so titles line up from row to row and plugin to plugin,
/// and accessories line up along the trailing edge, level with the title. At accessibility text
/// sizes the accessory moves below the title, where it has the row's width. The accessory's own
/// label is hidden, since the row's title names it; VoiceOver still reads it. A
/// ``DebugDrawerActionRow`` in the details lays its buttons out inline, for actions on this row
/// alone.
///
/// ```swift
/// DebugDrawerRow("Spoof Location", systemImage: "location", isOn: $isSpoofing)
/// DebugDrawerRow("Camera", systemImage: "camera") {
///     Text("NSCameraUsageDescription")
/// } accessory: {
///     Text("Allowed")
/// }
/// ```
///
/// The type exists in every build so a plugin's body compiles unchanged in release, where it
/// draws nothing.
public struct DebugDrawerRow<Details: View, Accessory: View>: View {
    let title: String
    let systemImage: String?
    let details: Details
    let accessory: Accessory

    /// - Parameters:
    ///   - title: What the row is ("Camera").
    ///   - systemImage: An SF Symbol beside the title, or `nil` for none.
    ///   - details: Lines below the title, in the drawer's secondary text.
    ///   - accessory: What sits at the trailing edge.
    public init(
        _ title: String,
        systemImage: String? = nil,
        @ViewBuilder details: () -> Details,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.systemImage = systemImage
        self.details = details()
        self.accessory = accessory()
    }

    public var body: some View {
        #if DEBUG
            DrawerRowLayout(title: title, systemImage: systemImage, details: details, accessory: accessory)
        #else
            EmptyView()
        #endif
    }
}

public extension DebugDrawerRow where Details == EmptyView {
    /// A row with no details.
    ///
    /// - Parameters:
    ///   - title: What the row is.
    ///   - systemImage: An SF Symbol beside the title, or `nil` for none.
    ///   - accessory: What sits at the trailing edge.
    init(_ title: String, systemImage: String? = nil, @ViewBuilder accessory: () -> Accessory) {
        self.init(title, systemImage: systemImage, details: { EmptyView() }, accessory: accessory)
    }
}

public extension DebugDrawerRow where Details == EmptyView, Accessory == Toggle<Text> {
    /// A row that turns a setting on and off, its switch at the trailing edge.
    ///
    /// - Parameters:
    ///   - title: The setting, which also labels the switch for VoiceOver.
    ///   - systemImage: An SF Symbol beside the title, or `nil` for none.
    ///   - isOn: Whether the setting is on.
    init(_ title: String, systemImage: String? = nil, isOn: Binding<Bool>) {
        self.init(title, systemImage: systemImage, details: { EmptyView() }, accessory: { Toggle(isOn: isOn) { Text(title) } })
    }
}

#if DEBUG
    /// The row's face.
    struct DrawerRowLayout<Details: View, Accessory: View>: View {
        let title: String
        let systemImage: String?
        let details: Details
        let accessory: Accessory
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 20 * .debugDrawerTextScale
        @ScaledMetric(relativeTo: .body) private var padding = DrawerSpacing.rowPadding

        var body: some View {
            let stacked = dynamicTypeSize.isAccessibilitySize
            let layout = stacked
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: padding / 2))
                // Centred: a switch whose label is hidden reports a first baseline below itself,
                // which dropped it under the title.
                : AnyLayout(HStackLayout(alignment: .center, spacing: 8))
            // Aligned on the title's own baseline rather than the column's first baseline, which
            // merges every child's: on iOS a Toggle, Slider or Stepper with its label hidden
            // reports one well above the title, which lifted the icon onto a line of its own.
            HStack(alignment: .rowTitleBaseline, spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .debugDrawerFont(.body)
                        .foregroundStyle(DrawerPalette.secondaryText)
                        .frame(width: iconWidth)
                        .alignmentGuide(.rowTitleBaseline) { $0[.firstTextBaseline] }
                        .accessibilityHidden(true)
                }
                VStack(alignment: .leading, spacing: 3) {
                    layout {
                        Text(title)
                            .debugDrawerFont(.body)
                            .foregroundStyle(DrawerPalette.text)
                            .fixedSize(horizontal: false, vertical: true)
                            .alignmentGuide(.rowTitleBaseline) { $0[.firstTextBaseline] }
                            // Takes the width the accessory leaves, which pushes it to the trailing edge.
                            .frame(maxWidth: stacked ? nil : .infinity, alignment: .leading)
                            .accessibilityElement(children: .combine)
                        accessory
                            .labelsHidden()
                            .debugDrawerFont(.body)
                    }
                    details
                        .debugDrawerFont(.secondary)
                        .foregroundStyle(DrawerPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .environment(\.isInDrawerRow, true)
            .padding(.vertical, padding)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    extension VerticalAlignment {
        /// The first baseline of a row's title, which the icon beside it sits on.
        fileprivate static let rowTitleBaseline = VerticalAlignment(RowTitleBaseline.self)
    }

    /// The row's title baseline; a view that doesn't set it reports its first text baseline.
    private enum RowTitleBaseline: AlignmentID {
        static func defaultValue(in context: ViewDimensions) -> CGFloat {
            context[.firstTextBaseline]
        }
    }
#endif
