// The DocC articles' examples (Sources/DebugDrawer/DebugDrawer.docc), verbatim, so the articles
// cannot drift from the code. Examples an article shares with the README are pinned in
// READMEExamplesTests.swift.

#if DEBUG
    import DebugDrawer
    import SwiftUI
    import Testing

    // InstallingInSwiftUI.md
    struct OrdersApp: App {
        init() {
            DebugDrawer.shared.registerGlobal(CachePlugin())
        }

        var body: some Scene {
            WindowGroup {
                OrdersRootView()
                    .debugDrawer()
            }
        }
    }

    // InstallingInSwiftUI.md
    struct OrdersRootView: View {
        var body: some View {
            Text("Orders")
                .onTapGesture(count: 3) {
                    DebugDrawer.shared.toggle()
                }
        }
    }

    // WritingPlugins.md
    struct OrderPlugin: DebugDrawerPlugin {
        let orderID: String

        var title = "Order"
        var icon = "shippingbox"

        var contentIdentifier: String {
            orderID
        }

        var body: some View {
            DebugDrawerKeyValueRow("Order ID", value: orderID)
        }
    }

    // WritingPlugins.md
    struct OrderDetailView: View {
        let orderID: String

        var body: some View {
            Text("Order \(orderID)")
                .debugLocalPlugin(OrderPlugin(orderID: orderID))
        }
    }

    // WritingPlugins.md
    struct JobsPlugin: DebugDrawerPlugin {
        var title = "Jobs"
        var icon = "gearshape.2"
        var category = "Background"

        var body: some View {
            Text("2 jobs failed")
        }

        var headerAccessory: some View {
            DebugDrawerIssueCount(.error, count: 2)
        }

        var hud: Text? {
            Text("2 failed")
        }
    }

    // BuildingPluginViews.md
    struct ServerSettingsView: View {
        @State private var usesStaging = false

        var body: some View {
            DebugDrawerSection("Server") {
                DebugDrawerRow("Use staging", systemImage: "server.rack", isOn: $usesStaging)
                DebugDrawerKeyValueRow("Host", value: usesStaging ? "staging.example.com" : "api.example.com")
                DebugDrawerKeyValueRow("API key", value: "k-12345", redacted: DebugDrawerRedaction.mask)
            } footer: {
                Text("Applies to the next request.")
            }
            DebugDrawerActionRow {
                DebugDrawerCopyButton("Copy Host") { usesStaging ? "staging.example.com" : "api.example.com" }
                Button("Reconnect") {}
            } trailing: {
                Button("Sign Out", role: .destructive) {}
                    .debugDrawerButtonStyle(.destructive)
            }
        }
    }

    @MainActor
    @Suite("Documentation examples")
    struct DocumentationExamplesTests {
        @Test("Installing in SwiftUI: the app registers its global plugins when it starts")
        func installingInSwiftUI() {
            let expectedTitle = "Cache"

            _ = OrdersApp()

            let actual = DebugDrawer.shared.globalPlugins.map(\.title)
            // Leave the shared drawer as the other suites expect it, within this one main-actor turn.
            DebugDrawer.shared.unregisterGlobal(id: CachePlugin().id)
            #expect(actual.contains(expectedTitle))
        }

        @Test("Writing plugins: a local plugin's ID is its type's name and its content follows the order")
        func localPlugin() {
            let sut = OrderPlugin(orderID: "42")
            let expectedID = "OrderPlugin"
            let expectedContentIdentifier = "42"

            let actual = AnyDebugDrawerPlugin(sut)

            #expect(actual.id == expectedID)
            #expect(sut.contentIdentifier == expectedContentIdentifier)
        }

        @Test("Writing plugins: a stale local registration's token leaves the newer one in place")
        func localPluginTokens() {
            let stale = DebugDrawer.shared.registerLocal(OrderPlugin(orderID: "1"))
            let current = DebugDrawer.shared.registerLocal(OrderPlugin(orderID: "2"))

            DebugDrawer.shared.unregisterLocal(id: "OrderPlugin", token: stale)

            let actual = DebugDrawer.shared.localPlugins.map(\.id)
            // Leave the shared drawer as the other suites expect it, within this one main-actor turn.
            DebugDrawer.shared.unregisterLocal(id: "OrderPlugin", token: current)
            #expect(actual.filter { $0 == "OrderPlugin" }.count == 1)
            #expect(!DebugDrawer.shared.localPlugins.contains { $0.id == "OrderPlugin" })
        }

        @Test("Writing plugins: a plugin declares its category, header accessory and HUD readout")
        func headerAndHUD() {
            let expectedCategory = "Background"

            let actual = AnyDebugDrawerPlugin(JobsPlugin())

            #expect(actual.category == expectedCategory)
            #expect(actual.headerAccessory != nil)
            #expect(actual.hasHUD)
        }

        @Test("Release builds: the calls that set the drawer up need no #if DEBUG")
        func releaseBuilds() throws {
            let reportsEndpoint = try #require(URL(string: "https://bugs.example.com/reports"))
            let previous = DebugDrawer.shared.reportUploader

            DebugDrawer.shared.registerGlobal(CachePlugin())
            DebugDrawer.shared.reportUploader = TeamReportUploader(endpoint: reportsEndpoint)

            let actual = DebugDrawer.shared.reportUploader as? TeamReportUploader
            // Leave the shared drawer as the other suites expect it, within this one main-actor turn.
            DebugDrawer.shared.reportUploader = previous
            DebugDrawer.shared.unregisterGlobal(id: CachePlugin().id)
            #expect(actual?.endpoint == reportsEndpoint)
        }
    }

    // Views render on the Mac; ViewInspector is linked on Apple platforms only.
    #if os(macOS)
        import AppKit
        import ViewInspector

        // InstallingInSwiftUI.md
        final class InvoiceWindowController: NSWindowController {
            @objc func toggleDebugDrawer(_: Any?) {
                guard let window else { return }
                DebugDrawer.shared.toggle(in: window)
            }
        }

        @MainActor
        @Suite("Documentation examples: windows")
        struct DocumentationWindowExamplesTests {
            @Test("Installing in SwiftUI: a window controller opens the drawer in its own window, attaching it first")
            func toggleInWindow() throws {
                // Borderless and far off screen: ordered in, so the drawer's panel can be, but never seen.
                let window = NSWindow(
                    contentRect: CGRect(x: -30000, y: -30000, width: 900, height: 600),
                    styleMask: .borderless, backing: .buffered, defer: false
                )
                window.isReleasedWhenClosed = false
                window.orderFront(nil)
                defer { window.close() }
                let sut = InvoiceWindowController(window: window)

                sut.toggleDebugDrawer(nil)

                // The drawer's panel is a child window of the window it opens in.
                let actual = window.childWindows?.contains(where: \.isVisible) == true
                DebugDrawer.shared.toggle(in: window)
                #expect(actual)
            }
        }

        @MainActor
        @Suite("Documentation examples: views")
        struct DocumentationViewExamplesTests {
            @Test("Building a plugin's view: the settings view shows its rows, masks the key and offers its actions")
            func buildingPluginViews() throws {
                let sut = ServerSettingsView()
                let expectedTexts: Set = [
                    "Server", "Use staging", "Host", "api.example.com", "API key", DebugDrawerRedaction.mask,
                    "Applies to the next request.", "Reconnect", "Sign Out"
                ]
                let secret = "k-12345"

                let actual = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }

                #expect(expectedTexts.isSubset(of: Set(actual)))
                #expect(!actual.contains(secret))
            }
        }
    #endif
#endif
