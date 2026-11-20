#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// Create Report for the plugins shown, then the drawer's report result: the zip to share, and
    /// Send Report when the sidecar set an uploader (`DebugDrawer.shared.reportUploader`).
    struct SidecarReportBar: View {
        @ObservedObject var connection: DebugDrawerSidecarConnection
        // The sidecar's uploader and redaction rules, set on its drawer as in a debug build.
        @ObservedObject private var drawer = DebugDrawer.shared
        @State private var result: DrawerReportResult.State?

        var body: some View {
            if let result {
                DrawerReportResult(state: result, send: drawer.reportUploader.map { uploader in { send($0, with: uploader) } }) {
                    self.result = nil
                }
            } else {
                HStack {
                    Spacer()
                    Button("Create Report", systemImage: "doc.zipper", action: createReport)
                        .debugDrawerButtonStyle(.secondary)
                        .disabled(connection.hosted.isEmpty)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
        }

        private func createReport() {
            result = .creating
            do {
                result = try .ready(connection.createReport(redaction: drawer.redaction))
            } catch {
                result = .failed("The report couldn't be written.")
            }
        }

        private func send(_ archive: URL, with uploader: any DebugDrawerReportUploader) {
            Task {
                await DrawerReportResult.State.send(archive, with: uploader) { result = $0 }
            }
        }
    }
#endif
