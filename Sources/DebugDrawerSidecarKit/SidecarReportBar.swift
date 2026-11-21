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
        @Environment(\.sidecarPluginLayout) private var layout

        var body: some View {
            if let result {
                DrawerReportResult(state: result, send: drawer.reportUploader.map { uploader in { send($0, with: uploader) } }) {
                    self.result = nil
                }
            } else {
                HStack {
                    // At the bar's trailing end; a list's row starts at its leading edge.
                    if layout == .picker {
                        Spacer()
                    }
                    Button("Create Report", systemImage: "doc.zipper", action: createReport)
                        .debugDrawerButtonStyle(.secondary)
                        .disabled(connection.hosted.isEmpty)
                }
                .sidecarBarPadding()
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
