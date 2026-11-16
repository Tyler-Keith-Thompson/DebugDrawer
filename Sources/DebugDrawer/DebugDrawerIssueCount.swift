import SwiftUI

/// How many issues of one severity a plugin has, as Xcode's activity view counts them: the issue
/// glyph, then the count in figures of one width ("⚠︎ 4"). Put it in a plugin's
/// ``DebugDrawerPlugin/headerAccessory``, so the count shows while the plugin is closed.
///
/// VoiceOver reads it as the count and what it counts ("4 warnings").
///
/// ```swift
/// var headerAccessory: some View {
///     DebugDrawerIssueCount(.error, count: reports.count)
/// }
/// ```
///
/// The type exists in every build so a plugin's header compiles unchanged in release, where it
/// draws nothing.
public struct DebugDrawerIssueCount: View {
    let severity: DebugDrawerIssueGlyph.Severity
    let count: Int

    /// - Parameters:
    ///   - severity: Which glyph to draw.
    ///   - count: How many there are.
    public init(_ severity: DebugDrawerIssueGlyph.Severity, count: Int) {
        self.severity = severity
        self.count = count
    }

    public var body: some View {
        #if DEBUG
            DrawerIssueCountFace(count: self)
        #else
            EmptyView()
        #endif
    }
}

#if DEBUG
    extension DebugDrawerIssueCount {
        /// What VoiceOver reads: the count and what it counts ("1 error", "4 warnings").
        var spokenLabel: String {
            let noun = switch severity {
            case .error: count == 1 ? "error" : "errors"
            case .warning: count == 1 ? "warning" : "warnings"
            case .ok: "OK"
            case .neutral: "unknown"
            }
            return "\(count.formatted()) \(noun)"
        }
    }

    /// The issue count's face: the glyph and the figures.
    struct DrawerIssueCountFace: View {
        let count: DebugDrawerIssueCount
        @ScaledMetric(relativeTo: .body) private var gap = DrawerSpacing.itemGap

        var body: some View {
            HStack(spacing: gap / 2) {
                DebugDrawerIssueGlyph(count.severity)
                Text(count.count, format: .number)
                    .debugDrawerFont(.value)
                    .foregroundStyle(DrawerPalette.secondaryText)
            }
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(count.spokenLabel)
        }
    }
#endif
