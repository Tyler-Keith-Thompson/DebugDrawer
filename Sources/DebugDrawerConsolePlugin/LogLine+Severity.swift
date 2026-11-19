import DebugDrawer

// The glyph is the drawer's view vocabulary, so it is worked out here, beside the views, rather
// than on the line the model holds.
extension LogLine.Level {
    /// The issue glyph a line of this level carries: an error for an error or a fault, none
    /// otherwise. os_log has no warning level (`Logger.warning` logs at the error level), so no
    /// level draws the warning glyph.
    var severity: DebugDrawerIssueGlyph.Severity? {
        switch self {
        case .error, .fault: .error
        case .debug, .info, .notice: nil
        }
    }
}
