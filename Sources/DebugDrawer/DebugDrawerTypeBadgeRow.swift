import SwiftUI

/// A binary in a list of them, as Xcode badges a file by its type: a rounded square with a letter
/// (A for the app, in the accent color; F for a framework; D for a dylib, in gray), the name, an
/// optional version at the trailing edge, and the path below in monospaced tertiary type, cut in
/// the middle until tapped (``DebugDrawerCodeText``).
///
/// ```swift
/// DebugDrawerTypeBadgeRow("Charts", kind: .framework, path: library.path, version: "5.1.0")
/// ```
///
/// The type exists in every build so a plugin's body compiles unchanged in release, where it
/// draws nothing.
public struct DebugDrawerTypeBadgeRow: View {
    /// What kind of binary the row lists, which picks its badge's letter and color.
    public enum Kind: CaseIterable, Sendable {
        /// The app's own executable: A, in the accent color.
        case app
        /// A framework bundle: F.
        case framework
        /// A dynamic library: D, in gray.
        case dylib
    }

    let name: String
    let kind: Kind
    let path: String
    let detail: String?
    let version: String?

    /// A row for one loaded binary, its kind shown as a badge.
    ///
    /// - Parameters:
    ///   - name: The binary's name ("Charts").
    ///   - kind: Which badge it gets.
    ///   - path: Where it was loaded from.
    ///   - detail: A second monospaced line below the path, such as its UUID and load address;
    ///     `nil` for none.
    ///   - version: Its version, at the trailing edge; `nil` for none.
    public init(_ name: String, kind: Kind, path: String, detail: String? = nil, version: String? = nil) {
        self.name = name
        self.kind = kind
        self.path = path
        self.detail = detail
        self.version = version
    }

    public var body: some View {
        #if DEBUG
            DrawerTypeBadgeRowLayout(row: self)
        #else
            EmptyView()
        #endif
    }
}

#if DEBUG
    /// The type badge row's face.
    struct DrawerTypeBadgeRowLayout: View {
        let row: DebugDrawerTypeBadgeRow
        @ScaledMetric(relativeTo: .body) private var badge = DrawerSpacing.glyph
        @ScaledMetric(relativeTo: .body) private var padding = DrawerSpacing.rowPadding
        @ScaledMetric(relativeTo: .body) private var gap = DrawerSpacing.itemGap
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            // At accessibility sizes the badge sits above the name, so the text has the row's width.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: gap))
            layout {
                Text(row.kind.letter)
                    .debugDrawerFont(.secondary)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .frame(width: badge, height: badge)
                    .background(row.kind.color, in: RoundedRectangle(cornerRadius: DrawerSpacing.badgeRadius))
                    .alignmentGuide(.firstTextBaseline) { $0[.bottom] - $0.height * 0.15 }
                    .accessibilityLabel(row.kind.name)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(alignment: .firstTextBaseline, spacing: gap) {
                        Text(row.name)
                            .debugDrawerFont(.body)
                            .foregroundStyle(DrawerPalette.text)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: gap)
                        if let version = row.version {
                            Text(version)
                                .debugDrawerFont(.code)
                                .foregroundStyle(DrawerPalette.secondaryText)
                        }
                    }
                    Group {
                        DebugDrawerCodeText(row.path)
                        if let detail = row.detail {
                            DebugDrawerCodeText(detail)
                        }
                    }
                    .foregroundStyle(DrawerPalette.tertiaryText)
                }
            }
            .padding(.vertical, padding)
        }
    }

    extension DebugDrawerTypeBadgeRow.Kind {
        fileprivate var letter: String {
            switch self {
            case .app: "A"
            case .framework: "F"
            case .dylib: "D"
            }
        }

        fileprivate var color: Color {
            switch self {
            case .app: DrawerPalette.accent
            case .framework: DrawerPalette.framework
            case .dylib: DrawerPalette.systemGray
            }
        }

        /// What VoiceOver reads for the badge.
        var name: String {
            switch self {
            case .app: "App"
            case .framework: "Framework"
            case .dylib: "Dynamic library"
            }
        }
    }
#endif
