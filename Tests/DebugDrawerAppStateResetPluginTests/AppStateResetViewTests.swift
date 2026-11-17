// ViewInspector is linked on Apple platforms only, and the views are tested on the Mac.
#if os(macOS)
    @testable import DebugDrawer
    @testable import DebugDrawerAppStateResetPlugin
    import Foundation
    import SwiftUI
    import Testing
    import ViewInspector

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct AppStateResetViewTests {
        @Test("Each category is a row with its summary and a checkbox; unticking one takes it out of the selection")
        func rows() throws {
            var selection = Set(ResetCategory.allCases)
            let binding = Binding(get: { selection }, set: { selection = $0 })
            let sut = AppStateResetView(
                state: .ready(ResetPlanFixture.plan), selection: binding, includesDebugDrawer: .constant(false),
                restartStyle: .relaunch, refresh: {}, reset: { _ in }
            )
            let expectedSummaries = [
                "4 keys", "2 items", "3 items · \(ResetPlan.bytes(4_252_400))", "1 item · \(ResetPlan.bytes(8_600_000))", "3 cookies"
            ]

            let rows = try sut.inspect().findAll(ResetCategoryRow.self)
            let summaries = try expectedSummaries.map { try sut.inspect().find(text: $0).string() }
            try rows[1].find(ViewType.Toggle.self).tap()

            #expect(rows.count == 7)
            #expect(try rows.map { try $0.actualView().category } == ResetCategory.allCases)
            #expect(summaries == expectedSummaries)
            #expect(selection == Set(ResetCategory.allCases).subtracting([.keychain]))
        }

        @Test("Reset… opens the confirmation, and is unavailable with nothing selected or while loading")
        func resetOpensConfirmation() async throws {
            let sut = AppStateResetView(
                state: .ready(ResetPlanFixture.plan), selection: .constant([.files]), includesDebugDrawer: .constant(false),
                restartStyle: .quit, refresh: {}, reset: { _ in }
            )
            let none = AppStateResetView(
                state: .ready(ResetPlanFixture.plan), selection: .constant([]), includesDebugDrawer: .constant(false),
                restartStyle: .quit, refresh: {}, reset: { _ in }
            )
            let loading = AppStateResetView(
                state: .loading, selection: .constant([.files]), includesDebugDrawer: .constant(false),
                restartStyle: .quit, refresh: {}, reset: { _ in }
            )
            var before = true
            var after = false

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    before = try view.actualView().isConfirming
                    try view.find(button: "Reset…").tap()
                }
                try await sut.inspection.inspect { view in
                    after = try view.actualView().isConfirming
                }
            }

            #expect(!before)
            #expect(after)
            #expect(try none.inspect().find(button: "Reset…").isDisabled())
            #expect(try loading.inspect().find(button: "Reset…").isDisabled())
            #expect(try loading.inspect().find(button: "Refresh").isDisabled())
            _ = try loading.inspect().find(text: "Reading the app's state…")
        }

        @Test("Refresh refreshes, and the DebugDrawer switch sets whether its own settings go too")
        func refreshAndDebugDrawer() throws {
            var refreshes = 0
            var includes = false
            let sut = AppStateResetView(
                state: .ready(ResetPlanFixture.plan), selection: .constant([]),
                includesDebugDrawer: Binding(get: { includes }, set: { includes = $0 }),
                restartStyle: .relaunch, refresh: { refreshes += 1 }, reset: { _ in }
            )

            try sut.inspect().find(button: "Refresh").tap()
            // The last switch: the seven categories' come first.
            try sut.inspect().findAll(ViewType.Toggle.self).last?.tap()

            #expect(refreshes == 1)
            #expect(includes)
        }

        @Test("A row's lines are hidden until Show Details, which lists each with its detail")
        func rowDetails() async throws {
            let lines = ResetPlanFixture.plan.lines(of: .files)
            let sut = ResetCategoryRow(category: .files, summary: "3 items", lines: lines, problem: nil, isSelected: .constant(true))
            var hidden: [String] = []
            var shown: [String] = []

            try await ViewHosting.host(sut) {
                try await sut.inspection.inspect { view in
                    hidden = try view.findAll(PlanLineRow.self).map { try $0.actualView().line.text }
                    try view.find(button: "Show details").tap()
                }
                try await sut.inspection.inspect { view in
                    shown = try view.findAll(PlanLineRow.self).map { try $0.actualView().line.text }
                    _ = try view.find(button: "Hide details")
                }
            }

            #expect(hidden.isEmpty)
            #expect(shown == ["Documents/Drafts", "Documents/notes.txt", "Application Support/orders.sqlite"])
        }

        @Test("A row with nothing to list has no Show Details; one that can't be read says why")
        func rowWithoutLines() throws {
            let sut = ResetCategoryRow(
                category: .keychain, summary: "Unavailable", lines: [], problem: "A required entitlement isn't present. (-34018)",
                isSelected: .constant(true)
            )

            let problem = try sut.inspect().find(text: "A required entitlement isn't present. (-34018)").string()

            #expect(problem == "A required entitlement isn't present. (-34018)")
            #expect(throws: (any Error).self) { try sut.inspect().find(button: "Show details") }
        }

        @Test("The confirmation lists exactly the selected categories' lines, in order, and nothing of the others")
        func confirmationListsSelection() throws {
            let plan = ResetPlanFixture.plan
            let categories: [ResetCategory] = [.userDefaults, .cookies, .urlCache]
            let sut = ResetConfirmationView(plan: plan, categories: categories, restartStyle: .relaunch, cancel: {}, reset: {}, resetAndRestart: {})
            let expected = categories.flatMap { plan.lines(of: $0) }

            let actual = try sut.inspect().findAll(PlanLineRow.self).map { try $0.actualView().line }
            let headings = try sut.inspect().findAll(ConfirmationCategorySection.self).map { try $0.actualView().category }

            #expect(actual == expected)
            #expect(headings == categories)
        }

        @Test("For every selection, the confirmation's lines are exactly the plan's for the categories selected")
        func confirmationMatchesPlanForEverySelection() throws {
            let plan = ResetPlanFixture.plan
            let all = plan.categories
            for mask in 0 ..< (1 << all.count) {
                let categories = all.indices.filter { mask & (1 << $0) != 0 }.map { all[$0] }
                let sut = ResetConfirmationView(plan: plan, categories: categories, restartStyle: .quit, cancel: {}, reset: {}, resetAndRestart: {})
                let expected = categories.flatMap { plan.lines(of: $0) }

                let actual = try sut.inspect().findAll(PlanLineRow.self).map { try $0.actualView().line }

                #expect(actual == expected, "\(categories)")
            }
        }

        @Test("The confirmation's buttons: Cancel, Reset, and Reset and Relaunch on macOS")
        func confirmationButtonsRelaunch() throws {
            var calls: [String] = []
            let sut = ResetConfirmationView(
                plan: ResetPlanFixture.plan, categories: [.files], restartStyle: .relaunch,
                cancel: { calls.append("cancel") }, reset: { calls.append("reset") }, resetAndRestart: { calls.append("restart") }
            )

            try sut.inspect().find(button: "Cancel").tap()
            try sut.inspect().find(button: "Reset").tap()
            try sut.inspect().find(button: "Reset and Relaunch").tap()

            #expect(calls == ["cancel", "reset", "restart"])
            #expect(throws: (any Error).self) { try sut.inspect().find(text: ResetConfirmationView.quitNote) }
        }

        @Test("Where the app can only quit, the button says Reset and Quit and the note says to open it again")
        func confirmationButtonsQuit() throws {
            let sut = ResetConfirmationView(
                plan: ResetPlanFixture.plan, categories: [.files], restartStyle: .quit, cancel: {}, reset: {}, resetAndRestart: {}
            )

            let note = try sut.inspect().find(text: ResetConfirmationView.quitNote).string()

            _ = try sut.inspect().find(button: "Reset and Quit")
            #expect(note.contains("Open it again from the Home Screen"))
        }

        @Test("A selected category with nothing in it says so in the confirmation")
        func confirmationNothingToDelete() throws {
            var plan = ResetPlanFixture.plan
            plan.files = []
            let sut = ResetConfirmationView(plan: plan, categories: [.files], restartStyle: .quit, cancel: {}, reset: {}, resetAndRestart: {})

            _ = try sut.inspect().find(text: "Nothing to delete.")
            _ = try sut.inspect().find(text: "Files: Empty")
        }

        @Test("After a reset each category says Cleared with its count, or what wasn't deleted and why, and a held restart says so")
        func results() throws {
            let result = ResetResult(outcomes: [
                .userDefaults: .cleared(4),
                .files: .failed(cleared: 2, failures: [.file("Documents/Drafts", reason: "Permission denied")]),
                .urlCache: .cleared(1)
            ])
            let sut = ResetResultSection(result: result, restart: .heldForFailures)

            let texts = try sut.inspect().findAll(ViewType.Text.self).map { try $0.string() }

            #expect(texts.contains("4 keys deleted"))
            #expect(texts.contains("2 items deleted"))
            #expect(texts.contains("Documents/Drafts: Permission denied"))
            #expect(texts.contains("Something wasn't deleted, so the app kept running for it to be read."))
        }

        @Test("The finished state shows the results above the rows")
        func finishedState() throws {
            let result = ResetResult(outcomes: [.cookies: .cleared(3)])
            let sut = AppStateResetView(
                state: .finished(ResetPlanFixture.plan, result, .failed(RelaunchFailure(message: "Can't open"))), selection: .constant([]),
                includesDebugDrawer: .constant(false), restartStyle: .relaunch, refresh: {}, reset: { _ in }
            )

            _ = try sut.inspect().find(ResetResultSection.self)
            _ = try sut.inspect().find(text: "Can't open")
            _ = try sut.inspect().find(text: "3 cookies deleted")
        }

        @Test("The header counts the selected categories")
        func header() throws {
            let none = AppStateResetHeaderReadout(count: 0)
            let three = AppStateResetHeaderReadout(count: 3)

            #expect(try none.inspect().text().string() == "None selected")
            #expect(try three.inspect().text().string() == "3 selected")
        }
    }
#endif
