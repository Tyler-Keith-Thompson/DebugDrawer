import SwiftUI

/// The glyph Xcode's issue navigator uses for an issue's severity: a red octagon with an
/// exclamation mark for an error, a yellow triangle for a warning, a green circle with a check
/// for ok, and a gray circle with a question mark for what isn't decided. Each has its own
/// shape, so it reads without its color.
///
/// The glyph is 18 points on iOS and 14 on the Mac, and grows with the text. VoiceOver reads it
/// as its severity ("Error"); where a word beside it says the same, hide it with
/// `accessibilityHidden(true)`.
///
/// The type exists in every build so a plugin's body compiles unchanged in release, where it
/// draws nothing.
public struct DebugDrawerIssueGlyph: View {
    /// What the glyph says about the thing beside it.
    public enum Severity: CaseIterable, Sendable {
        /// Broken or refused: a red octagon.
        case error
        /// Partly working or needing attention: a yellow triangle.
        case warning
        /// Working or granted: a green circle with a check.
        case ok
        /// Not decided or not known: a gray circle with a question mark.
        case neutral
    }

    let severity: Severity

    /// - Parameter severity: Which glyph to draw.
    public init(_ severity: Severity) {
        self.severity = severity
    }

    public var body: some View {
        #if DEBUG
            DrawerIssueGlyphFace(severity: severity)
        #else
            EmptyView()
        #endif
    }
}

#if DEBUG
    /// The glyph's face: the severity's symbol, its mark and fill in two colors, at the glyph size.
    struct DrawerIssueGlyphFace: View {
        let severity: DebugDrawerIssueGlyph.Severity
        @ScaledMetric(relativeTo: .body) private var size = DrawerSpacing.glyph

        var body: some View {
            Image(systemName: severity.symbol)
                .resizable()
                .scaledToFit()
                .symbolRenderingMode(.palette)
                .foregroundStyle(severity.mark, severity.fill)
                .frame(width: size, height: size)
                .accessibilityLabel(severity.name)
        }
    }

    extension DebugDrawerIssueGlyph.Severity {
        fileprivate var symbol: String {
            switch self {
            case .error: "exclamationmark.octagon.fill"
            case .warning: "exclamationmark.triangle.fill"
            case .ok: "checkmark.circle.fill"
            case .neutral: "questionmark.circle.fill"
            }
        }

        fileprivate var mark: Color {
            self == .warning ? DrawerPalette.warningMark : .white
        }

        fileprivate var fill: Color {
            switch self {
            case .error: DrawerPalette.error
            case .warning: DrawerPalette.warning
            case .ok: DrawerPalette.ok
            case .neutral: DrawerPalette.systemGray
            }
        }

        /// What VoiceOver reads for the glyph.
        var name: String {
            switch self {
            case .error: "Error"
            case .warning: "Warning"
            case .ok: "OK"
            case .neutral: "Unknown"
            }
        }
    }
#endif
