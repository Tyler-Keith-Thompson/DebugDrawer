// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    import DebugDrawer
    @testable import DebugDrawerAppInfoPlugin
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct AppInfoPluginViewTests {
        @Test("The plugin's view words the transport's snapshot: the build, footprint, uptime, network and screen")
        func viewDrawsTheSnapshot() throws {
            let snapshot = AppInfoSnapshot(
                bundle: BundleInfo(identifier: "com.example.App", version: "1.2.3", build: "45"),
                buildMetadata: AppInfoBuildMetadata(gitCommit: "4f9c2e1"),
                device: DeviceInfo(
                    operatingSystemName: "macOS", operatingSystemVersion: "Version 26.0", isSandboxed: true,
                    screen: DeviceInfo.Screen(width: 1512, height: 982, scale: 2)
                ),
                footprintMB: 182.4,
                uptime: 134,
                network: .wiredEthernet
            )
            let sut = AppInfoPluginView(
                transport: DebugDrawerPluginTransport(initial: snapshot, snapshots: AsyncStream { $0.finish() }, send: { _ in })
            )

            let texts = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }

            #expect(texts.contains("com.example.App"))
            #expect(texts.contains("4f9c2e1"))
            #expect(texts.contains("182.4 MB"))
            #expect(texts.contains("2m 14s"))
            #expect(texts.contains("Ethernet"))
            #expect(texts.contains("1512×982 @2x"))
            #expect(texts.contains("Sandbox"))
        }

        @Test("Refresh sends the refresh command, and nothing else")
        func refreshSendsTheCommand() throws {
            var sent: [AppInfoCommand.Action] = []
            let sut = AppInfoPluginView(
                transport: DebugDrawerPluginTransport(
                    initial: AppInfoSnapshot(), snapshots: AsyncStream { $0.finish() }, send: { sent.append($0.action) }
                )
            )

            try sut.inspect().find(button: "Refresh").tap()

            #expect(sent == [.refresh])
        }
    }
#endif
