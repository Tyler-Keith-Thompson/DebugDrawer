// Reading the environment happens once, as the mirror is made at launch, so it must stay cheap even
// for a large profile: a team profile listing many devices runs to hundreds of kilobytes, most of
// it before the closing tag the search looks for.
import DebugDrawerNotifications
import Foundation
import Testing

@Suite
struct ProvisioningProfileSpeedTests {
    @Test("A profile of 20,000 devices, its plist after 2 MiB of signature bytes, is read in under half a second")
    func largeProfile() {
        let devices = (0 ..< 20000).map { "<string>00008030-\(String($0, radix: 16))</string>" }.joined()
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <plist version="1.0"><dict><key>ProvisionedDevices</key><array>\(devices)</array>\
        <key>Entitlements</key><dict><key>aps-environment</key><string>production</string></dict></dict></plist>
        """
        let profile = Data(repeating: 0x30, count: 2 << 20) + Data(plist.utf8) + Data(repeating: 0xA0, count: 1 << 20)
        let clock = ContinuousClock()

        var actual: PushEnvironment.Server?
        let elapsed = clock.measure {
            actual = PushEnvironment.provisioningProfileServer(profile)
        }

        #expect(actual == .production)
        #expect(elapsed < .milliseconds(500))
    }
}
