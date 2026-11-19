#if DEBUG
    @testable import DebugDrawerAppInfoPlugin
    import Foundation
    import Testing

    @Suite("App Info build metadata")
    @MainActor
    struct AppInfoBuildMetadataTests {
        @Test("The commit, branch and CI build passed at install appear in the Build section and in Copy Info")
        func installParameter() throws {
            let metadata = AppInfoBuildMetadata(gitCommit: "4f9c2e1", gitBranch: "release/2.4", ciBuildNumber: "812")
            let expected: [AppInfoFacts.Fact] = [
                .init(label: "Commit", value: "4f9c2e1"),
                .init(label: "Branch", value: "release/2.4"),
                .init(label: "CI Build", value: "812")
            ]

            let actual = AppInfoFacts(snapshot: AppInfoSnapshot(buildMetadata: metadata))

            let build = try #require(actual.sections.first { $0.title == "Build" })
            #expect(Array(build.facts.suffix(3)) == expected)
            #expect(actual.report.contains("Commit: 4f9c2e1\nBranch: release/2.4\nCI Build: 812"))
        }

        @Test("The commit, branch and CI build are read from Info.plist keys when not passed")
        func infoPlistKeys() throws {
            let info: [String: Any] = [
                "CFBundleIdentifier": "com.example.metadata.\(UUID().uuidString)",
                "CFBundleShortVersionString": "2.4.0",
                "CFBundleVersion": "97",
                "DebugDrawerGitCommit": "a1b2c3d",
                "DebugDrawerGitBranch": "main",
                "DebugDrawerCIBuildNumber": "1042"
            ]
            let url = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).bundle", directoryHint: .isDirectory)
            #if os(macOS)
                let contents = url.appending(path: "Contents", directoryHint: .isDirectory)
            #else
                let contents = url
            #endif
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: contents.appending(path: "Info.plist"))
            let bundle = try #require(Bundle(url: url))
            let expected: [AppInfoFacts.Fact] = [
                .init(label: "Version", value: "2.4.0"),
                .init(label: "Build", value: "97"),
                .init(label: "Commit", value: "a1b2c3d"),
                .init(label: "Branch", value: "main"),
                .init(label: "CI Build", value: "1042")
            ]

            let actual = AppInfoFacts(snapshot: AppInfoSnapshot(bundle: _BundleInfoSource(bundle: bundle).read()))

            let build = try #require(actual.sections.first { $0.title == "Build" })
            #expect(Array(build.facts.dropFirst()) == expected)
            #expect(actual.report.contains("Commit: a1b2c3d\nBranch: main\nCI Build: 1042"))
        }

        @Test("A value passed at install wins over the Info.plist's; one not passed comes from the plist")
        func parameterWins() {
            let info: [String: Any] = ["DebugDrawerGitCommit": "plist-sha", "DebugDrawerGitBranch": "plist-branch"]
            let expected = AppInfoBuildMetadata(gitCommit: "passed-sha", gitBranch: "plist-branch", ciBuildNumber: nil)

            let actual = AppInfoBuildMetadata(gitCommit: "passed-sha").filled(from: info)

            #expect(actual == expected)
        }

        @Test("An empty or non-string Info.plist value counts as missing")
        func emptyValues() {
            let info: [String: Any] = ["DebugDrawerGitCommit": "", "DebugDrawerGitBranch": 7]

            let actual = AppInfoBuildMetadata().filled(from: info)

            #expect(actual == AppInfoBuildMetadata())
        }

        @Test("With nothing passed and no keys, the Build section shows a dash for each")
        func noMetadata() throws {
            let expected: [AppInfoFacts.Fact] = [
                .init(label: "Commit", value: "—"),
                .init(label: "Branch", value: "—"),
                .init(label: "CI Build", value: "—")
            ]

            let actual = AppInfoFacts(snapshot: AppInfoSnapshot(bundle: _BundleInfoSource().read()))

            let build = try #require(actual.sections.first { $0.title == "Build" })
            #expect(Array(build.facts.suffix(3)) == expected)
        }
    }
#endif
