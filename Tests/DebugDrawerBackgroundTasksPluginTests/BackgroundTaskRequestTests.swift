#if DEBUG
    @testable import DebugDrawerBackgroundTasksPlugin
    import Foundation
    import Testing

    @Suite
    struct BackgroundTaskRequestTests {
        @Test("An app refresh request reads as App Refresh, with no conditions")
        func appRefresh() {
            let kind = BackgroundTaskRequest.Kind.appRefresh
            let expected = "App Refresh"

            let actual = kind.summary

            #expect(actual == expected)
            #expect(kind.requirements.isEmpty)
        }

        @Test("A processing request names each condition it waits for", arguments: [
            (false, false, "Processing"),
            (true, false, "Processing · Needs network"),
            (false, true, "Processing · Needs external power"),
            (true, true, "Processing · Needs network · Needs external power")
        ])
        func processing(network: Bool, power: Bool, expected: String) {
            let kind = BackgroundTaskRequest.Kind.processing(requiresNetworkConnectivity: network, requiresExternalPower: power)

            let actual = kind.summary

            #expect(actual == expected)
        }

        @Test("A request class the drawer doesn't know reads as its class name")
        func other() {
            let kind = BackgroundTaskRequest.Kind.other(className: "BGHealthResearchTaskRequest")
            let expected = "BGHealthResearchTaskRequest"

            let actual = kind.summary

            #expect(actual == expected)
        }

        @Test("Each scheduler error code maps to its failure; any other keeps the system's message", arguments: [
            (1, BackgroundTaskSubmitFailure.unavailable),
            (2, .tooManyPendingTaskRequests),
            (3, .notPermitted),
            (4, .other(message: "The task couldn't run now")),
            (0, .other(message: "The task couldn't run now"))
        ])
        func failures(code: Int, expected: BackgroundTaskSubmitFailure) {
            let actual = BackgroundTaskSubmitFailure(schedulerErrorCode: code, message: "The task couldn't run now")

            #expect(actual == expected)
        }

        @Test("A failure the system describes shows the system's words")
        func otherExplanation() {
            let failure = BackgroundTaskSubmitFailure.other(message: "The task couldn't run now")
            let expected = "The task couldn't run now"

            let actual = failure.explanation

            #expect(actual == expected)
        }

        @Test("A Schedule on its way, or refused, shows on its own row only")
        func scheduleShown() {
            let failed = ScheduleState.failed(identifier: "a", kind: .appRefresh, failure: .unavailable)
            let scheduling = ScheduleState.scheduling(identifier: "a", kind: .processing)

            #expect(failed.shown(for: "a") == failed)
            #expect(failed.shown(for: "b") == .idle)
            #expect(scheduling.shown(for: "a") == scheduling)
            #expect(scheduling.shown(for: "b") == .idle)
            #expect(ScheduleState.idle.shown(for: "a") == .idle)
        }
    }
#endif
