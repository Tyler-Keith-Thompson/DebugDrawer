// What finding the declared permissions costs at launch. The plugin exists in debug builds only,
// so it is measured there; `--config=release` builds this target without it, and runs
// ReleaseInstallTests instead.
#if DEBUG
    @testable import DebugDrawerPermissionsPlugin
    import Foundation
    import Testing

    // install() reads the Info.plist on the main actor at startup, and every time the app becomes
    // active the model builds its rows again. A large app's Info.plist (two thousand keys, every
    // permission declared) is read in about a millisecond on an Apple silicon Mac in debug builds,
    // and the rows are built in well under one; the bounds are many times that, so a loaded machine
    // passes and a change that scans the dictionary once per key fails.
    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct PermissionsLoadTests {
        @Test("Reading a 2,000-key Info.plist takes under 50 ms, and building every permission's row under 10 ms")
        func largeInfoPlist() {
            /// Stands in for the frameworks: every status at once.
            @MainActor
            final class InstantAuthority: PermissionAuthority {
                func status(of _: DeclaredPermission) async -> PermissionStatus {
                    .authorized
                }

                func request(_: DeclaredPermission) async {}

                func stop() {}
            }
            /// Reports no changes.
            @MainActor
            final class SilentChanges: PermissionChangeSource {
                func observe(_: @escaping @MainActor () async -> Void) {}

                func stop() {}
            }
            var infoDictionary: [String: Any] = Dictionary(uniqueKeysWithValues: (0 ..< 1950).map { ("Key\($0)", "Value \($0)" as Any) })
            for key in PermissionKind.recognized.flatMap(\.keys) {
                infoDictionary[key] = "Because the app needs it"
            }
            for index in 0 ..< 50 {
                infoDictionary["NSCustom\(index)UsageDescription"] = "Something else"
            }
            let clock = ContinuousClock()
            var declared: [DeclaredPermission] = []

            let readTime = clock.measure {
                declared = DeclaredPermission.declared(in: infoDictionary)
            }
            let model = PermissionsModel(permissions: declared, authority: InstantAuthority(), changes: SilentChanges())
            var rows: [PermissionRowState] = []
            let rowsTime = clock.measure {
                rows = model.rows
            }

            print("Permissions: reading \(infoDictionary.count) keys takes \(readTime); building \(rows.count) rows \(rowsTime)")
            #expect(infoDictionary.count > 1990)
            #expect(declared.count == PermissionKind.recognized.count + 50)
            #expect(readTime < .milliseconds(50))
            #expect(rowsTime < .milliseconds(10))
        }
    }
#endif
