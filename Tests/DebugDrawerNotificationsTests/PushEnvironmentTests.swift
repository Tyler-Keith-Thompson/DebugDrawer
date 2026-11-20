#if DEBUG
    @testable import DebugDrawerNotifications
    import Foundation
    import Testing

    @Suite
    struct PushEnvironmentTests {
        @Test("A profile whose aps-environment is development names the sandbox")
        func developmentProfile() {
            let profile = Data([0x30, 0x82, 0x0B, 0x4F]) + Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Name</key><string>Example Development</string>
                <key>Entitlements</key>
                <dict>
                    <key>aps-environment</key><string>development</string>
                </dict>
            </dict>
            </plist>
            """.utf8) + Data([0xA0, 0x82, 0x0F, 0x00])

            let actual = PushEnvironment.provisioningProfileServer(profile)

            #expect(actual == .sandbox)
        }

        @Test("A profile whose aps-environment is production names production")
        func productionProfile() {
            let profile = Data([0x30, 0x80]) + Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict><key>Entitlements</key><dict>\
            <key>aps-environment</key><string>production</string></dict></dict></plist>
            """.utf8)

            let actual = PushEnvironment.provisioningProfileServer(profile)

            #expect(actual == .production)
        }

        @Test("A Mac profile's com.apple.developer.aps-environment is read too")
        func macProfile() {
            let profile = Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict><key>Entitlements</key><dict>\
            <key>com.apple.developer.aps-environment</key><string>development</string></dict></dict></plist>
            """.utf8)

            let actual = PushEnvironment.provisioningProfileServer(profile)

            #expect(actual == .sandbox)
        }

        @Test("A profile without the entitlement, or with a value APNs doesn't name, says nothing")
        func noEntitlement() {
            let withoutEntitlement = Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict><key>Entitlements</key><dict>\
            <key>application-identifier</key><string>TEAM.com.example</string></dict></dict></plist>
            """.utf8)
            let unknownValue = Data("""
            <?xml version="1.0" encoding="UTF-8"?>
            <plist version="1.0"><dict><key>Entitlements</key><dict>\
            <key>aps-environment</key><string>staging</string></dict></dict></plist>
            """.utf8)

            let actualWithout = PushEnvironment.provisioningProfileServer(withoutEntitlement)
            let actualUnknown = PushEnvironment.provisioningProfileServer(unknownValue)

            #expect(actualWithout == nil)
            #expect(actualUnknown == nil)
        }

        @Test("Bytes that hold no property list, an unclosed one, or nothing say nothing")
        func unreadable() {
            let garbage = Data([0x00, 0xFF, 0x10, 0x20])
            let unclosed = Data("<?xml version=\"1.0\"?><plist><dict><key>Entitlements</key>".utf8)

            #expect(PushEnvironment.provisioningProfileServer(garbage) == nil)
            #expect(PushEnvironment.provisioningProfileServer(unclosed) == nil)
            #expect(PushEnvironment.provisioningProfileServer(Data()) == nil)
        }

        @Test("development is the sandbox, production production, and nothing else is a server")
        func entitlementValues() {
            #expect(PushEnvironment.Server(entitlementValue: "development") == .sandbox)
            #expect(PushEnvironment.Server(entitlementValue: "production") == .production)
            #expect(PushEnvironment.Server(entitlementValue: "Production") == nil)
            #expect(PushEnvironment.Server(entitlementValue: "") == nil)
        }

        #if os(macOS)
            @Test("A test runner, signed without the push entitlement, detects no environment")
            func unsignedRunner() {
                let actual = PushEnvironment.detected()

                #expect(actual == nil)
            }
        #endif
    }
#endif
