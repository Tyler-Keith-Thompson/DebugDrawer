#if DEBUG
    @testable import DebugDrawerBackgroundTasksPlugin
    import Foundation
    import Testing

    @Suite
    struct BackgroundTaskDeclarationTests {
        @Test("The permitted identifiers are listed in the Info.plist's order, and fetch and processing allow both kinds")
        func identifiers() {
            let infoDictionary: [String: Any] = [
                "BGTaskSchedulerPermittedIdentifiers": ["com.example.refresh", "com.example.cleanup"],
                "UIBackgroundModes": ["processing", "remote-notification", "fetch"]
            ]
            let expected = BackgroundTaskDeclaration(
                identifiers: [PermittedIdentifier("com.example.refresh"), PermittedIdentifier("com.example.cleanup")],
                kinds: [.appRefresh, .processing]
            )

            let actual = BackgroundTaskDeclaration(infoDictionary: infoDictionary)

            #expect(actual == expected)
        }

        @Test("A missing key lists no identifiers and no kinds")
        func missing() {
            let expected = BackgroundTaskDeclaration(identifiers: [], kinds: [])

            let actual = BackgroundTaskDeclaration(infoDictionary: ["CFBundleName": "Orders"])

            #expect(actual == expected)
        }

        @Test("An empty list, or a key that isn't an array, lists nothing")
        func emptyOrWrongType() {
            let empty: [String: Any] = ["BGTaskSchedulerPermittedIdentifiers": [String](), "UIBackgroundModes": [String]()]
            let wrongType: [String: Any] = ["BGTaskSchedulerPermittedIdentifiers": "com.example.refresh", "UIBackgroundModes": "fetch"]
            let expected = BackgroundTaskDeclaration(identifiers: [], kinds: [])

            let actualEmpty = BackgroundTaskDeclaration(infoDictionary: empty)
            let actualWrongType = BackgroundTaskDeclaration(infoDictionary: wrongType)

            #expect(actualEmpty == expected)
            #expect(actualWrongType == expected)
        }

        @Test("A repeated identifier is listed once, where it first appears; empty strings and other values are dropped")
        func duplicates() {
            let infoDictionary: [String: Any] = [
                "BGTaskSchedulerPermittedIdentifiers": ["b", "a", "b", "", 7, "a", "c"] as [Any],
                "UIBackgroundModes": ["fetch", "fetch"]
            ]
            let expected = BackgroundTaskDeclaration(
                identifiers: [PermittedIdentifier("b"), PermittedIdentifier("a"), PermittedIdentifier("c")],
                kinds: [.appRefresh]
            )

            let actual = BackgroundTaskDeclaration(infoDictionary: infoDictionary)

            #expect(actual == expected)
        }

        @Test("One identifier and processing alone allow only processing")
        func one() {
            let infoDictionary: [String: Any] = [
                "BGTaskSchedulerPermittedIdentifiers": ["com.example.cleanup"],
                "UIBackgroundModes": ["processing"]
            ]
            let expected = BackgroundTaskDeclaration(identifiers: [PermittedIdentifier("com.example.cleanup")], kinds: [.processing])

            let actual = BackgroundTaskDeclaration(infoDictionary: infoDictionary)

            #expect(actual == expected)
        }

        @Test("An identifier ending in * is a wildcard; one with a * inside isn't")
        func wildcard() {
            let wildcard = PermittedIdentifier("com.example.export.*")
            let inside = PermittedIdentifier("com.example.*.export")

            #expect(wildcard.isWildcard)
            #expect(!inside.isWildcard)
        }

        @Test("The copied commands call the scheduler's simulate selectors with the identifier as an Objective-C string")
        func commands() {
            let identifier = PermittedIdentifier("com.example.refresh")
            let expectedLaunch =
                #"e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.example.refresh"]"#
            let expectedExpiration =
                #"e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateExpirationForTaskWithIdentifier:@"com.example.refresh"]"#

            let actualLaunch = identifier.simulateLaunchCommand
            let actualExpiration = identifier.simulateExpirationCommand

            #expect(actualLaunch == expectedLaunch)
            #expect(actualExpiration == expectedExpiration)
        }

        @Test("A quote or backslash in the identifier is escaped, so the command still parses")
        func escaping() {
            let identifier = PermittedIdentifier(#"odd"id\x"#)
            let expected = #"e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"odd\"id\\x"]"#

            let actual = identifier.simulateLaunchCommand

            #expect(actual == expected)
        }
    }
#endif
