/// A plugin that adds its data to the bug report the drawer's Create Report button writes.
///
/// Adopt it beside ``DebugDrawerPlugin``; a plugin that doesn't is left out of the report. The
/// report puts a contributor's files in a folder named after the plugin's title.
///
/// The protocol, ``DebugDrawerReport`` and ``DebugDrawerRedaction`` exist in every build, so a
/// conformance compiles unchanged in release, where the drawer, and so the report, doesn't exist.
public protocol DebugDrawerReportContributor {
    /// Adds the plugin's files to `report`, with every value `redaction` calls sensitive masked.
    ///
    /// - Parameters:
    ///   - report: The plugin's part of the report; files added here land in the plugin's folder.
    ///   - redaction: The rules of the drawer writing the report, its
    ///     ``DebugDrawer/redaction``, to apply to what's added.
    @MainActor func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction)
}
