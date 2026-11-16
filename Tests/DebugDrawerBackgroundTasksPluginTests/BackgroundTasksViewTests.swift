// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    import DebugDrawer
    @testable import DebugDrawerBackgroundTasksPlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct BackgroundTasksViewTests {
        @Test("Each permitted identifier is listed, with whether a request for it is pending")
        func identifiers() throws {
            let sut = PermittedIdentifiersSection(
                declaration: BackgroundTaskDeclaration(
                    identifiers: [PermittedIdentifier("com.example.refresh"), PermittedIdentifier("com.example.cleanup")],
                    kinds: [.appRefresh, .processing]
                ),
                pending: [BackgroundTaskRequest(id: "com.example.refresh", earliestBeginDate: nil, kind: .appRefresh)],
                schedule: .idle
            ) { _, _ in }

            let heading = try sut.inspect().find(text: "Permitted Identifiers (2)").string()
            let refresh = try sut.inspect().find(text: "com.example.refresh").string()
            let cleanup = try sut.inspect().find(text: "com.example.cleanup").string()
            let pending = try sut.inspect().find(text: "Pending · App Refresh").string()
            let idle = try sut.inspect().find(text: "Not scheduled").string()

            #expect(heading == "Permitted Identifiers (2)")
            #expect(refresh == "com.example.refresh")
            #expect(cleanup == "com.example.cleanup")
            #expect(pending == "Pending · App Refresh")
            #expect(idle == "Not scheduled")
        }

        @Test("With no permitted identifiers the section names the key the Info.plist lacks")
        func noIdentifiers() throws {
            let sut = PermittedIdentifiersSection(
                declaration: BackgroundTaskDeclaration(identifiers: [], kinds: [.appRefresh]), pending: [], schedule: .idle
            ) { _, _ in }
            let expected = "The Info.plist lists no BGTaskSchedulerPermittedIdentifiers."

            let actual = try sut.inspect().find(text: expected).string()

            #expect(actual == expected)
        }

        @Test("With neither fetch nor processing in the background modes the section warns and offers no Schedule")
        func noModes() throws {
            let sut = PermittedIdentifiersSection(
                declaration: BackgroundTaskDeclaration(identifiers: [PermittedIdentifier("com.example.refresh")], kinds: []),
                pending: [], schedule: .idle
            ) { _, _ in }
            let expected = "UIBackgroundModes lists neither fetch nor processing, so the system runs no request."

            let actual = try sut.inspect().find(text: expected).string()

            #expect(actual == expected)
            #expect(throws: (any Error).self) { try sut.inspect().find(button: "Schedule App Refresh") }
            #expect(throws: (any Error).self) { try sut.inspect().find(button: "Schedule Processing") }
        }

        @Test("Each Schedule button schedules its identifier as its kind")
        func schedule() throws {
            var scheduled: [String] = []
            let sut = PermittedIdentifiersSection(
                declaration: BackgroundTaskDeclaration(identifiers: [PermittedIdentifier("com.example.refresh")], kinds: [.appRefresh, .processing]),
                pending: [], schedule: .idle
            ) { identifier, kind in
                scheduled.append("\(identifier) \(kind.title)")
            }
            let expected = ["com.example.refresh App Refresh", "com.example.refresh Processing"]

            try sut.inspect().find(button: "Schedule App Refresh").tap()
            try sut.inspect().find(button: "Schedule Processing").tap()

            #expect(scheduled == expected)
        }

        @Test("Each identifier offers its LLDB commands to copy from a menu, each labeled for VoiceOver")
        func commands() throws {
            let sut = PermittedIdentifierRow(
                identifier: PermittedIdentifier("com.example.refresh"), pendingRequest: nil, kinds: [.appRefresh], schedule: .idle
            ) { _ in }

            let menu = try sut.inspect().find(ViewType.Menu.self).accessibilityLabel().string()
            let launch = try sut.inspect().find(button: "Copy Launch Command").accessibilityLabel().string()
            let expiration = try sut.inspect().find(button: "Copy Expiration Command").accessibilityLabel().string()

            #expect(menu == "Copy an LLDB command for com.example.refresh")
            #expect(launch == "Copy Launch Command for com.example.refresh")
            #expect(expiration == "Copy Expiration Command for com.example.refresh")
        }

        @Test("A refusal shows on its row with its reason, and Schedule waits while one is on its way")
        func refusal() throws {
            let failed = PermittedIdentifierRow(
                identifier: PermittedIdentifier("com.example.refresh"), pendingRequest: nil, kinds: [.appRefresh],
                schedule: .failed(identifier: "com.example.refresh", kind: .appRefresh, failure: .unavailable)
            ) { _ in }
            let scheduling = PermittedIdentifierRow(
                identifier: PermittedIdentifier("com.example.refresh"), pendingRequest: nil, kinds: [.appRefresh],
                schedule: .scheduling(identifier: "com.example.refresh", kind: .appRefresh)
            ) { _ in }
            let expected = "App Refresh refused — Unavailable. \(BackgroundTaskSubmitFailure.unavailable.explanation)"

            let actual = try failed.inspect().find(text: expected).string()
            let progress = try scheduling.inspect().find(text: "Scheduling…").string()

            #expect(actual == expected)
            #expect(progress == "Scheduling…")
            #expect(try scheduling.inspect().find(button: "Schedule App Refresh").isDisabled())
            #expect(try !failed.inspect().find(button: "Schedule App Refresh").isDisabled())
        }

        @Test("A wildcard says what it is for and offers neither Schedule nor commands")
        func wildcard() throws {
            let sut = PermittedIdentifierRow(
                identifier: PermittedIdentifier("com.example.export.*"), pendingRequest: nil, kinds: [.appRefresh], schedule: .idle
            ) { _ in }
            let expected = "A wildcard, for continued processing tasks the app starts itself."

            let actual = try sut.inspect().find(text: expected).string()

            #expect(actual == expected)
            #expect(throws: (any Error).self) { try sut.inspect().find(button: "Schedule App Refresh") }
            #expect(throws: (any Error).self) { try sut.inspect().find(button: "Copy Launch Command") }
        }

        @Test("A pending request shows its identifier, kind and conditions, and its earliest begin date")
        func pendingRequest() throws {
            let sut = PendingTaskRequestRow(request: BackgroundTaskRequest(
                id: "com.example.cleanup", earliestBeginDate: Date(timeIntervalSince1970: 1_800_000_000),
                kind: .processing(requiresNetworkConnectivity: true, requiresExternalPower: true)
            )) {}
                .environment(\.locale, Locale(identifier: "en_US_POSIX"))
                .environment(\.timeZone, TimeZone(identifier: "UTC") ?? .gmt)
            let style = Date.FormatStyle(
                date: .abbreviated, time: .standard, locale: Locale(identifier: "en_US_POSIX"), timeZone: TimeZone(identifier: "UTC") ?? .gmt
            )
            let expectedDate = Date(timeIntervalSince1970: 1_800_000_000).formatted(style)

            let identifier = try sut.inspect().find(text: "com.example.cleanup").string()
            let kind = try sut.inspect().find(text: "Processing · Needs network · Needs external power").string()
            let date = try sut.inspect().find(text: expectedDate).string()

            #expect(identifier == "com.example.cleanup")
            #expect(kind == "Processing · Needs network · Needs external power")
            #expect(date == expectedDate)
        }

        @Test("A request with no earliest begin date says it may run as soon as the system allows")
        func noDate() throws {
            let sut = PendingTaskRequestRow(request: BackgroundTaskRequest(id: "a", earliestBeginDate: nil, kind: .appRefresh)) {}
            let expected = "No earliest begin date: as soon as the system allows"

            let actual = try sut.inspect().find(text: expected).string()

            #expect(actual == expected)
        }

        @Test("Each request's Cancel cancels it; Cancel All and Refresh do theirs")
        func cancel() throws {
            var cancelled: [String] = []
            var cancelledAll = 0
            var refreshed = 0
            let sut = PendingRequestsSection(
                requests: [
                    BackgroundTaskRequest(id: "com.example.refresh", earliestBeginDate: nil, kind: .appRefresh),
                    BackgroundTaskRequest(id: "com.example.cleanup", earliestBeginDate: nil, kind: .appRefresh)
                ],
                onCancel: { cancelled.append($0) },
                onCancelAll: { cancelledAll += 1 },
                onRefresh: { refreshed += 1 }
            )

            try sut.inspect().find(ViewType.Button.self) { try $0.accessibilityLabel().string() == "Cancel com.example.cleanup" }.tap()
            try sut.inspect().find(button: "Cancel All").tap()
            try sut.inspect().find(button: "Refresh").tap()

            #expect(cancelled == ["com.example.cleanup"])
            #expect(cancelledAll == 1)
            #expect(refreshed == 1)
        }

        @Test("With no pending requests the section says so and offers Refresh but not Cancel All")
        func noRequests() throws {
            let sut = PendingRequestsSection(requests: [], onCancel: { _ in }, onCancelAll: {}, onRefresh: {})

            let heading = try sut.inspect().find(text: "Pending Requests (0)").string()
            let empty = try sut.inspect().find(text: "No pending requests.").string()

            #expect(heading == "Pending Requests (0)")
            #expect(empty == "No pending requests.")
            #expect(throws: (any Error).self) { try sut.inspect().find(button: "Cancel All") }
            #expect(try sut.inspect().find(button: "Refresh").labelView().text().string() == "Refresh")
        }

        @Test("Before the first read the view says it is reading, and still explains the LLDB commands")
        func loading() throws {
            let sut = BackgroundTasksView(
                declaration: BackgroundTaskDeclaration(identifiers: [PermittedIdentifier("a")], kinds: [.appRefresh]),
                pending: .loading, schedule: .idle, actions: BackgroundTasksActions()
            )

            let reading = try sut.inspect().find(text: "Reading the pending requests…").string()
            let help = try sut.inspect().find(text: BackgroundTasksView.simulatingALaunch).string()

            #expect(reading == "Reading the pending requests…")
            #expect(help.contains("(lldb)"))
            #expect(throws: (any Error).self) { try sut.inspect().find(text: "a") }
        }

        @Test("The header counts the pending requests, and shows nothing when there are none")
        func headerAccessory() async throws {
            let scheduler = FakeBackgroundTaskScheduler(requests: [
                BackgroundTaskRequest(id: "a", earliestBeginDate: nil, kind: .appRefresh),
                BackgroundTaskRequest(id: "b", earliestBeginDate: nil, kind: .appRefresh)
            ])
            let model = BackgroundTasksModel(
                declaration: BackgroundTaskDeclaration(identifiers: [], kinds: []), client: scheduler, changes: FakeBackgroundTaskChangeSource()
            )
            await model.refresh()
            let sut = BackgroundTasksHeaderAccessory(model: model)

            let count = try sut.inspect().find(text: "2 pending")
            model.cancelAll()

            #expect(try count.accessibilityLabel().string() == "2 pending requests")
            #expect(throws: (any Error).self) { try sut.inspect().find(ViewType.Text.self) }
        }
    }
#endif
