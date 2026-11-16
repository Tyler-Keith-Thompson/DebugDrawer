import Foundation

/// Sends a finished bug report to wherever the host app's team collects them: an internal
/// endpoint, an issue tracker's webhook, a shared folder.
///
/// Assign one to `DebugDrawer.shared.reportUploader` and the drawer shows Send Report beside a
/// finished report. Until one is assigned the button is hidden and the report stays on the
/// device: the library makes no network request of its own, and nothing is sent but by the
/// uploader, when someone taps Send Report or Retry.
///
/// The protocol exists in every build, so a conformance compiles unchanged in release, where
/// there is no drawer to assign it to and nothing calls it.
public protocol DebugDrawerReportUploader: Sendable {
    /// Sends the report's zip.
    ///
    /// The archive stays where it is whether the upload succeeds or fails, so a failed upload
    /// can be retried with the same file and the report can still be shared.
    ///
    /// - Parameters:
    ///   - archive: The report's zip, as ``DebugDrawer/createReport(in:)`` wrote it.
    ///   - progress: Called with the fraction sent so far, from 0 to 1, from any thread; values
    ///     outside that range are clamped, and calls after `upload` returns are ignored.
    /// - Throws: Whatever stopped the upload. The drawer shows the error's
    ///   `localizedDescription`, so adopt `LocalizedError` to word it.
    func upload(_ archive: URL, progress: @escaping @Sendable (Double) -> Void) async throws
}
