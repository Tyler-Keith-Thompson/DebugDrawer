import SwiftUI

/// A row in the manner of Xcode's issue navigator: an issue glyph, the title with its status
/// after a dash in the secondary color ("Camera — Allowed"), an optional monospaced subline in the
/// tertiary color (an Info.plist key, say), any details below, and an optional accessory at the
/// trailing edge.
///
/// The status is a word, so the row never says something by color alone; VoiceOver reads the
/// title and status, and the glyph only when there is no status. A ``DebugDrawerActionRow`` in the
/// details holds actions on this row alone. At accessibility text sizes the glyph sits above the
/// title and the accessory below the details, so the text has the row's width.
///
/// ```swift
/// DebugDrawerIssueRow("Camera", status: "Denied", severity: .error, subline: "NSCameraUsageDescription") {
///     Text("Scans receipts")
///     DebugDrawerActionRow { Button("Open Settings", action: openSettings) }
/// }
/// ```
///
/// The type exists in every build so a plugin's body compiles unchanged in release, where it
/// draws nothing.
public struct DebugDrawerIssueRow<Details: View, Accessory: View>: View {
    let title: String
    let status: String?
    let severity: DebugDrawerIssueGlyph.Severity
    let subline: String?
    let details: Details
    let accessory: Accessory

    /// An issue row with details and an accessory.
    ///
    /// - Parameters:
    ///   - title: What the row is ("Camera").
    ///   - status: Its state in a word or two ("Allowed"), shown after a dash; `nil` for none.
    ///   - severity: The glyph before the title.
    ///   - subline: A monospaced line below the title, such as a key or a path, cut in the middle
    ///     until tapped (``DebugDrawerCodeText``); `nil` for none.
    ///   - details: Lines below, in the drawer's secondary text.
    ///   - accessory: What sits at the trailing edge, such as a button.
    public init(
        _ title: String,
        status: String? = nil,
        severity: DebugDrawerIssueGlyph.Severity,
        subline: String? = nil,
        @ViewBuilder details: () -> Details,
        @ViewBuilder accessory: () -> Accessory
    ) {
        self.title = title
        self.status = status
        self.severity = severity
        self.subline = subline
        self.details = details()
        self.accessory = accessory()
    }

    public var body: some View {
        #if DEBUG
            DrawerIssueRowLayout(row: self)
        #else
            EmptyView()
        #endif
    }
}

public extension DebugDrawerIssueRow where Accessory == EmptyView {
    /// An issue row with details and no accessory.
    ///
    /// - Parameters:
    ///   - title: What the row is.
    ///   - status: Its state in a word or two; `nil` for none.
    ///   - severity: The glyph before the title.
    ///   - subline: A monospaced line below the title; `nil` for none.
    ///   - details: Lines below, in the drawer's secondary text.
    init(
        _ title: String,
        status: String? = nil,
        severity: DebugDrawerIssueGlyph.Severity,
        subline: String? = nil,
        @ViewBuilder details: () -> Details
    ) {
        self.init(title, status: status, severity: severity, subline: subline, details: details) { EmptyView() }
    }
}

public extension DebugDrawerIssueRow where Details == EmptyView, Accessory == EmptyView {
    /// An issue row of a title, its status and a subline alone.
    ///
    /// - Parameters:
    ///   - title: What the row is.
    ///   - status: Its state in a word or two; `nil` for none.
    ///   - severity: The glyph before the title.
    ///   - subline: A monospaced line below the title; `nil` for none.
    init(_ title: String, status: String? = nil, severity: DebugDrawerIssueGlyph.Severity, subline: String? = nil) {
        self.init(title, status: status, severity: severity, subline: subline, details: { EmptyView() }, accessory: { EmptyView() })
    }
}

#if DEBUG
    /// The issue row's face.
    struct DrawerIssueRowLayout<Details: View, Accessory: View>: View {
        let row: DebugDrawerIssueRow<Details, Accessory>
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize
        @ScaledMetric(relativeTo: .body) private var padding = DrawerSpacing.rowPadding
        @ScaledMetric(relativeTo: .body) private var gap = DrawerSpacing.itemGap

        var body: some View {
            let stacked = dynamicTypeSize.isAccessibilitySize
            // At accessibility sizes the glyph sits above the title, so the text has the row's width.
            let layout = stacked
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: gap))
            layout {
                DebugDrawerIssueGlyph(row.severity)
                    .accessibilityHidden(row.status != nil)
                    // The glyph's middle sits on the middle of the title's first line.
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - $0.height * 0.15 }
                VStack(alignment: .leading, spacing: 2) {
                    title
                    if let subline = row.subline {
                        DebugDrawerCodeText(subline)
                            .foregroundStyle(DrawerPalette.tertiaryText)
                    }
                    row.details
                        .debugDrawerFont(.secondary)
                        .foregroundStyle(DrawerPalette.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                    if stacked {
                        row.accessory
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if !stacked {
                    row.accessory
                }
            }
            .environment(\.isInDrawerRow, true)
            .padding(.vertical, padding)
        }

        private var title: some View {
            Group {
                if let status = row.status {
                    Text("\(row.title)\(Text(" — \(status)").foregroundStyle(DrawerPalette.secondaryText))")
                } else {
                    Text(row.title)
                }
            }
            .debugDrawerFont(.body)
            .foregroundStyle(DrawerPalette.text)
            .fixedSize(horizontal: false, vertical: true)
        }
    }
#endif
