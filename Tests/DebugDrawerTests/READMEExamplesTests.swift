// The README's examples, verbatim, so the README cannot drift from the code.

#if DEBUG
    import DebugDrawer
    import SwiftUI
    import Testing

    struct CachePlugin: DebugDrawerPlugin {
        var title = "Cache"
        var icon = "trash" // an SF Symbol

        var body: some View {
            let usage = "\(URLCache.shared.currentDiskUsage / 1024) KB"
            DebugDrawerKeyValueRow("Disk usage", value: usage)
            DebugDrawerCopyButton("Copy Usage") { usage }
            Button("Clear URL cache") { URLCache.shared.removeAllCachedResponses() }
        }
    }

    struct SessionPlugin: DebugDrawerPlugin {
        var title = "Session"
        var icon = "person.crop.circle"

        var body: some View {
            Text("Signed in")
        }

        var actions: [DebugDrawerAction] {
            [
                DebugDrawerAction("Expire token", keywords: ["auth", "logout"]) {
                    UserDefaults.standard.removeObject(forKey: "authToken")
                }
            ]
        }
    }

    struct QueuePlugin: DebugDrawerPlugin {
        var title = "Queue"
        var icon = "tray.full"

        var body: some View {
            Text("3 jobs waiting")
        }

        var hud: Text? {
            Text("3 jobs")
        }
    }

    struct UploadsPlugin: DebugDrawerPlugin {
        var title = "Uploads"
        var icon = "arrow.up.circle"

        var body: some View {
            Text("No uploads")
        }
    }

    struct CartPlugin: DebugDrawerPlugin, DebugDrawerReportContributor {
        var title = "Cart"
        var icon = "cart"

        var body: some View {
            Text("2 items")
        }

        func contribute(to report: inout DebugDrawerReport, redaction: DebugDrawerRedaction) {
            report.add(text: "2 items", named: "cart.txt")
            let checkout = Data(#"{"card":"4111","token":"t0k3n"}"#.utf8)
            report.add(jsonData: redaction.redacting(json: checkout), named: "checkout.json")
        }
    }

    struct TeamReportUploader: DebugDrawerReportUploader {
        let endpoint: URL

        func upload(_ archive: URL, progress: @escaping @Sendable (Double) -> Void) async throws {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/zip", forHTTPHeaderField: "Content-Type")
            let (_, response) = try await URLSession.shared.upload(for: request, fromFile: archive)
            guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
                throw URLError(.badServerResponse)
            }
            progress(1)
        }
    }

    @MainActor
    @Suite("README examples")
    struct READMEExamplesTests {
        @Test("Sending reports")
        func sendingReports() throws {
            let reportsEndpoint = try #require(URL(string: "https://bugs.example.com/reports"))
            let previous = DebugDrawer.shared.reportUploader

            DebugDrawer.shared.reportUploader = TeamReportUploader(endpoint: reportsEndpoint)

            let actual = DebugDrawer.shared.reportUploader as? TeamReportUploader
            // Leave the shared drawer as the other suites expect it, within this one main-actor turn.
            DebugDrawer.shared.reportUploader = previous
            #expect(actual?.endpoint == reportsEndpoint)
        }

        @Test("Bug reports")
        func bugReports() throws {
            let previous = DebugDrawer.shared.redaction
            DebugDrawer.shared.redaction = .standard
            // Leave the shared drawer as the other suites expect it, within this one main-actor turn.
            defer {
                DebugDrawer.shared.unregisterGlobal(id: CartPlugin().id)
                DebugDrawer.shared.redaction = previous
            }

            DebugDrawer.shared.registerGlobal(CartPlugin())
            let zip = try DebugDrawer.shared.createReport() // the same zip the button makes

            defer { try? FileManager.default.removeItem(at: zip) }
            var contribution = DebugDrawerReport()
            CartPlugin().contribute(to: &contribution, redaction: DebugDrawer.shared.redaction)
            let checkout = try #require(contribution.files.last)
            #expect(zip.pathExtension == "zip")
            #expect(FileManager.default.fileExists(atPath: zip.path))
            #expect(contribution.files.map(\.name) == ["cart.txt", "checkout.json"])
            #expect(String(bytes: checkout.data, encoding: .utf8) == #"{"card":"4111","token":"[REDACTED]"}"#)
        }

        @Test("Usage")
        func usage() {
            let wasOpen = DebugDrawer.shared.isOpen

            // Global: registered once at startup, always in the drawer.
            DebugDrawer.shared.registerGlobal(CachePlugin())

            // The drawer, attached once to the root view.
            let root = Text("Home").debugDrawer()

            // Local: in the drawer while its view is on screen.
            let settings = Text("Settings").debugLocalPlugin(CachePlugin())

            // Open or close it from whatever trigger suits the app.
            DebugDrawer.shared.toggle()

            _ = (root, settings)
            #expect(DebugDrawer.shared.globalPlugins.contains { $0.title == "Cache" })
            #expect(DebugDrawer.shared.isOpen != wasOpen)

            // Leave the shared drawer as the other suites expect it, within this one main-actor turn.
            DebugDrawer.shared.toggle()
            DebugDrawer.shared.unregisterGlobal(id: CachePlugin().id)
        }

        @Test("Floating HUD")
        func floatingHUD() {
            let queue = AnyDebugDrawerPlugin(QueuePlugin())
            let uploads = AnyDebugDrawerPlugin(UploadsPlugin())

            #expect(queue.hasHUD)
            #expect(!uploads.hasHUD)
        }

        @Test("Badges and toasts")
        func badgesAndToasts() {
            let wasOpen = DebugDrawer.shared.isOpen
            DebugDrawer.shared.isOpen = false

            let uploads = UploadsPlugin()
            uploads.setBadge(2)
            uploads.postToast("Upload of report.pdf failed")
            let badge = DebugDrawer.shared.badges["UploadsPlugin"]
            let toast = DebugDrawer.shared.toast
            uploads.clearBadge()

            // Leave the shared drawer as the other suites expect it, within this one main-actor turn.
            DebugDrawer.shared.dismissToast()
            DebugDrawer.shared.isOpen = wasOpen
            #expect(badge == 2)
            #expect(toast?.pluginID == "UploadsPlugin")
            #expect(toast?.message == "Upload of report.pdf failed")
            #expect(DebugDrawer.shared.badges["UploadsPlugin"] == nil)
        }

        @Test("Redacting sensitive values")
        func redactingSensitiveValues() throws {
            let previous = DebugDrawer.shared.redaction

            DebugDrawer.shared.redact(
                headers: ["X-Api-Signature"],
                keys: ["pin"],
                jsonPaths: ["user.ssn", "cards.number"]
            )
            let actual = DebugDrawer.shared.redaction
            let body = Data(#"{"cards":[{"number":"4111","exp":"12/30"}],"user":{"ssn":"1"}}"#.utf8)
            let redactedBody = try #require(String(bytes: actual.redacting(json: body), encoding: .utf8))

            // Leave the shared drawer as the other suites expect it, within this one main-actor turn.
            DebugDrawer.shared.redaction = previous
            #expect(actual.masksHeader("x-api-signature"))
            #expect(actual.masksHeader("Authorization"))
            #expect(actual.masksKey("userPin"))
            #expect(redactedBody == #"{"cards":[{"exp":"12/30","number":"[REDACTED]"}],"user":{"ssn":"[REDACTED]"}}"#)
        }

        @Test("Searching plugins and actions")
        func searchingPluginsAndActions() {
            let expectedTitles = ["Expire token"]

            let actual = AnyDebugDrawerPlugin(SessionPlugin()).actions.map(\.title)

            #expect(actual == expectedTitles)
            #expect(AnyDebugDrawerPlugin(CachePlugin()).actions.isEmpty)
        }
    }
#endif
