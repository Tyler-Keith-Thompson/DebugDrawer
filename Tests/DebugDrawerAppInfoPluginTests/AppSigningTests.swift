#if DEBUG
    @testable import DebugDrawerAppInfoPlugin
    import Foundation
    import Testing

    @Suite("App signing")
    struct AppSigningTests {
        @Test("With no profile and no entitlements, as a simulator or unsigned Mac build, both are none")
        func nothing() {
            let source = FakeSigningInformation()

            let actual = AppSigning(reading: source)

            #expect(actual == AppSigning(profile: .none, entitlements: nil))
        }

        @Test("On a device, with a profile and no entitlements read from the app, the profile's are shown")
        func device() throws {
            let source = try FakeSigningInformation(profile: AppInfoFixtures.profileData())
            let expected = AppSigning(profile: .embedded(AppInfoFixtures.profile), entitlements: AppInfoFixtures.profile.entitlements)

            let actual = AppSigning(reading: source)

            #expect(actual == expected)
        }

        @Test("Entitlements read from the app itself win over the profile's")
        func ownEntitlementsWin() throws {
            let own = Entitlements(source: .codeSignature, entries: [Entitlement(key: "com.apple.security.app-sandbox", value: .boolean(true))])
            let source = try FakeSigningInformation(profile: AppInfoFixtures.profileData(), entitlements: own)

            let actual = AppSigning(reading: source)

            #expect(actual.entitlements == own)
            #expect(actual.profile == .embedded(AppInfoFixtures.profile))
        }

        @Test("A profile file that isn't a profile is unreadable, not a failure")
        func unreadable() {
            let source = FakeSigningInformation(profile: Data("garbage".utf8))

            let actual = AppSigning(reading: source)

            #expect(actual == AppSigning(profile: .unreadable, entitlements: nil))
        }

        @Test("The store reads the signing once, however often it is asked")
        @MainActor
        func storeReadsOnce() throws {
            let source = try FakeSigningInformation(profile: AppInfoFixtures.profileData())
            let sut = AppSigningStore(source: source)

            let first = sut.signing
            let second = sut.signing

            #expect(first == second)
            #expect(source.reads == 1)
        }

        @Test("The running test process has no provisioning profile, and reading its signing doesn't fail")
        func realProcess() {
            let sut = _SigningInformation()

            let actual = AppSigning(reading: sut)

            #expect(actual.profile == .none)
        }
    }
#endif
