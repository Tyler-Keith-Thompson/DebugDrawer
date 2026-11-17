#if DEBUG
    import Combine
    import Foundation

    /// Where the plugin is: one case per thing that can be true.
    enum ResetState: Hashable, Sendable {
        /// Reading what each category holds.
        case loading
        /// What each category would delete.
        case ready(ResetPlan)
        /// Deleting what the plan lists.
        case resetting(ResetPlan)
        /// Reset: what each category holds now, and what the reset did.
        case finished(ResetPlan, ResetResult, RestartOutcome)

        /// The plan the rows show, `nil` while it is first read.
        var plan: ResetPlan? {
            switch self {
            case .loading: nil
            case let .ready(plan), let .resetting(plan), let .finished(plan, _, _): plan
            }
        }
    }

    /// What became of a restart asked for with the reset.
    enum RestartOutcome: Hashable, Sendable {
        /// None was asked for, or the app is still running after one (its delegate refused to
        /// quit, say).
        case none
        /// Something wasn't deleted, so the app kept running for the failures to be read.
        case heldForFailures
        /// The new instance couldn't be launched.
        case failed(RelaunchFailure)
    }

    /// The categories picked, the plan for them, and the reset, on the main actor for the drawer.
    @MainActor
    final class AppStateResetModel: ObservableObject {
        @Published private(set) var state = ResetState.loading
        /// The categories a reset clears: all of them until some are unticked.
        @Published var selection: Set<ResetCategory>
        /// Whether DebugDrawer's own keys and files are cleared too. Off unless turned on.
        @Published private(set) var includesDebugDrawer = false

        let appState: AppState
        let process: any AppProcess

        /// - Parameters:
        ///   - appState: The app's state, behind its seams.
        ///   - process: The app's process, to relaunch or quit after a reset.
        init(appState: AppState, process: any AppProcess) {
            self.appState = appState
            self.process = process
            selection = Set(ResetCategory.allCases.filter { $0 != .appCleanup || appState.cleanup != nil })
        }

        /// How the app starts over after Reset and Relaunch (or Quit).
        var restartStyle: RestartStyle {
            process.restartStyle
        }

        /// Reads what each category holds again, unless a reset is running.
        func refresh() async {
            if case .resetting = state { return }
            let plan = await appState.plan(includingDebugDrawer: includesDebugDrawer)
            if case let .finished(_, result, restart) = state {
                state = .finished(plan, result, restart)
            } else {
                state = .ready(plan)
            }
        }

        /// Reads the plan the first time the plugin is shown.
        func loadIfNeeded() async {
            guard state == .loading else { return }
            await refresh()
        }

        /// Includes DebugDrawer's own keys and files, or keeps them, and reads the plan again.
        func setIncludesDebugDrawer(_ includes: Bool) async {
            includesDebugDrawer = includes
            await refresh()
        }

        /// Deletes what the plan lists for the selected categories, then reads the plan again.
        ///
        /// - Parameter restarting: Whether the app then relaunches (macOS) or quits. It doesn't
        ///   when something couldn't be deleted, so the failures can be read.
        func reset(restarting: Bool) async {
            guard let plan = state.plan, state != .resetting(plan) else { return }
            state = .resetting(plan)
            let result = await appState.reset(selection, of: plan)
            var restart = RestartOutcome.none
            if restarting {
                if result.hasFailures {
                    restart = .heldForFailures
                } else {
                    do throws(RelaunchFailure) {
                        try await process.restart()
                    } catch {
                        restart = .failed(error)
                    }
                }
            }
            state = .finished(await appState.plan(includingDebugDrawer: includesDebugDrawer), result, restart)
        }
    }
#endif
