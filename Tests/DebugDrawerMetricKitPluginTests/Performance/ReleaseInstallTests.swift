// The release stand-in. `--config=release` builds and runs only the performance targets, so this
// is where a test is compiled without DEBUG, as an app's release build is; in debug the file is
// empty, and MetricKitInstallExitTests checks the opposite.
#if !DEBUG
    import DebugDrawerMetricKitPlugin
    import Foundation
    import Testing

    @Suite
    struct ReleaseInstallTests {
        @MainActor
        @Test("In release, install and add compile and write nothing: not even the directory")
        func installKeepsNothing() {
            let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            defer { try? FileManager.default.removeItem(at: directory) }
            let kind: MetricKitPayloadKind = .diagnostics

            MetricKitPayloads.install(directory: directory)
            MetricKitPayloads.add(json: Data(#"{"crashDiagnostics":[]}"#.utf8), kind: kind)

            #expect(!FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)))
        }
    }
#endif
