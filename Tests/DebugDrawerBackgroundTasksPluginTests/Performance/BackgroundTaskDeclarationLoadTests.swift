// What reading the declaration costs at launch. The plugin exists in debug builds only, so it is
// measured there; `--config=release` builds this target without it, and runs ReleaseInstallTests
// instead.
#if DEBUG
    @testable import DebugDrawerBackgroundTasksPlugin
    import Foundation
    import Testing

    // install() reads the Info.plist on the main actor at startup. Ten thousand permitted
    // identifiers, half of them repeats, in a 2,000-key Info.plist are read in about a millisecond
    // on an Apple silicon Mac in debug builds; the bound is many times that, so a loaded machine
    // passes and a change that checks repeats by scanning the list for each identifier fails.
    @Suite(.timeLimit(.minutes(1)))
    struct BackgroundTaskDeclarationLoadTests {
        @Test("Reading 10,000 permitted identifiers, half of them repeats, takes under 50 ms")
        func manyIdentifiers() {
            var infoDictionary: [String: Any] = Dictionary(uniqueKeysWithValues: (0 ..< 2000).map { ("Key\($0)", "Value \($0)" as Any) })
            infoDictionary["BGTaskSchedulerPermittedIdentifiers"] = (0 ..< 10000).map { "com.example.task\($0 % 5000)" }
            infoDictionary["UIBackgroundModes"] = ["fetch", "processing"]
            let clock = ContinuousClock()
            var declaration = BackgroundTaskDeclaration(identifiers: [], kinds: [])

            let time = clock.measure {
                declaration = BackgroundTaskDeclaration(infoDictionary: infoDictionary)
            }

            print("Background Tasks: reading 10,000 identifiers takes \(time)")
            #expect(declaration.identifiers.count == 5000)
            #expect(time < .milliseconds(50))
        }
    }
#endif
