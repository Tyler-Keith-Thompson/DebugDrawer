#if DEBUG
    @testable import DebugDrawerRemote
    import Foundation
    import Network
    import Testing

    // Bonjour is checked through its configuration only: the service a listener would advertise,
    // and what a browse result becomes. Nothing here advertises or browses.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct BonjourServiceTests {
        @Test("The service type is _debugdrawer._tcp, the value NSBonjourServices lists")
        func serviceType() {
            let expected = "_debugdrawer._tcp"

            let actual = DebugDrawerBonjourService.type

            #expect(actual == expected)
        }

        @Test("The TXT record names the pairing version, the app, its bundle identifier and its platform")
        func txtRecord() {
            let expected = ["v": "1", "app": "Shop", "bundle": "com.example.shop", "os": "iOS"]

            let actual = DebugDrawerBonjourService.txtRecord(appName: "Shop", bundleIdentifier: "com.example.shop", platform: "iOS")

            #expect(actual == expected)
        }

        @Test("An app with no name or bundle identifier advertises the version and platform alone")
        func txtRecordWithoutBundle() {
            let expected = ["v": "1", "os": "macOS"]

            let actual = DebugDrawerBonjourService.txtRecord(appName: nil, bundleIdentifier: nil, platform: "macOS")

            #expect(actual == expected)
        }

        @Test("This app's TXT record carries the version and this platform")
        func currentTXTRecord() {
            #if os(macOS)
                let expectedPlatform = "macOS"
            #elseif targetEnvironment(macCatalyst)
                let expectedPlatform = "macCatalyst"
            #else
                let expectedPlatform = "iOS"
            #endif

            let actual = DebugDrawerBonjourService.currentTXTRecord()

            #expect(actual["v"] == "1")
            #expect(actual["os"] == expectedPlatform)
        }

        @Test("The listener's service has the type, the name asked for, the local domain and the TXT record")
        func listenerService() {
            let txtRecord = ["v": "1", "app": "Shop", "os": "iOS"]

            let actual = DebugDrawerBonjourService.listenerService(name: "QA iPad", txtRecord: txtRecord)

            #expect(actual.type == "_debugdrawer._tcp")
            #expect(actual.name == "QA iPad")
            #expect(actual.domain == nil)
            #expect(actual.txtRecordObject?.dictionary == txtRecord)
        }

        @Test("With no name, the listener's service takes the device's")
        func listenerServiceDefaultName() {
            let actual = DebugDrawerBonjourService.listenerService(name: nil, txtRecord: ["v": "1"])

            #expect(actual.name == nil)
        }

        @Test("Started, the browser lists the apps speaking this pairing version, by name, and stop forgets them")
        func browserListsDevices() {
            let browser = FakeServiceBrowser()
            let sut = DebugDrawerNetworkBrowser(browser: browser)
            let ipad = NWEndpoint.service(name: "QA iPad", type: "_debugdrawer._tcp", domain: "local.", interface: nil)
            let iphone = NWEndpoint.service(name: "Ana's iPhone", type: "_debugdrawer._tcp", domain: "local.", interface: nil)
            let old = NWEndpoint.service(name: "Old Build", type: "_debugdrawer._tcp", domain: "local.", interface: nil)
            let expected = [
                DebugDrawerNetworkDevice(
                    name: "Ana's iPhone", appName: "Shop", bundleIdentifier: "com.example.shop", platform: "iOS", endpoint: iphone
                ),
                DebugDrawerNetworkDevice(name: "QA iPad", appName: nil, bundleIdentifier: nil, platform: "iOS", endpoint: ipad)
            ]

            sut.start()
            sut.start()
            browser.find([
                BrowsedService(name: "QA iPad", endpoint: ipad, txtRecord: ["v": "1", "os": "iOS"]),
                BrowsedService(name: "Old Build", endpoint: old, txtRecord: ["v": "0"]),
                BrowsedService(
                    name: "Ana's iPhone", endpoint: iphone, txtRecord: ["v": "1", "app": "Shop", "bundle": "com.example.shop", "os": "iOS"]
                )
            ])
            let found = sut.devices
            sut.stop()

            #expect(browser.startCount == 1)
            #expect(found == expected)
            #expect(browser.cancelCount == 1)
            #expect(sut.devices.isEmpty)
            #expect(sut.isBrowsing == false)
        }
    }
#endif
