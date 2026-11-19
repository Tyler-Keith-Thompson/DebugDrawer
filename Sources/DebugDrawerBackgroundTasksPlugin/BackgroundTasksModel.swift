#if DEBUG
    import Combine
    import Foundation
    import os

    /// What the Info.plist declares and what the scheduler holds, read again on every change the
    /// source reports and after each of the drawer's own actions.
    @MainActor
    final class BackgroundTasksModel: ObservableObject {
        /// The permitted identifiers and the kinds the background modes allow; fixed at install.
        let declaration: BackgroundTaskDeclaration
        @Published private(set) var pending: PendingRequestsState = .loading
        @Published private(set) var schedule: ScheduleState = .idle

        private static let logger = Logger(subsystem: "DebugDrawerBackgroundTasksPlugin", category: "BackgroundTasksModel")
        private let client: any BackgroundTaskSchedulerClient
        /// Kept for the model's life: the source reports only while someone holds it.
        private let changes: any BackgroundTaskChangeSource
        /// When a scheduled request may begin: now, so a simulated launch has a request to run.
        private let now: () -> Date
        /// Counts reads, so a read that finishes after a later one began is dropped rather than
        /// overwriting newer state.
        private var latestRead = 0

        /// - Parameters:
        ///   - declaration: What the Info.plist declares.
        ///   - client: Reads and changes the scheduler's requests.
        ///   - changes: Says when to read them again; observed from now on.
        ///   - now: The current time, which a scheduled request begins no sooner than.
        init(
            declaration: BackgroundTaskDeclaration,
            client: any BackgroundTaskSchedulerClient,
            changes: any BackgroundTaskChangeSource,
            now: @escaping () -> Date = Date.init
        ) {
            self.declaration = declaration
            self.client = client
            self.changes = changes
            self.now = now
            changes.observe { [weak self] in await self?.refresh() }
        }

        /// Whether the model reads again on each change the source reports: from its creation
        /// until the last drawer uninstalls the plugin, and again once one installs it.
        private(set) var isObserving = true
        /// The drawers the plugin over this model is installed in.
        private var installedDrawers: Set<ObjectIdentifier> = []

        /// Counts `drawer` as one the plugin is installed in. If an uninstall stopped the model,
        /// observes the source again and reads the requests again.
        func install(in drawer: ObjectIdentifier) {
            installedDrawers.insert(drawer)
            guard !isObserving else { return }
            isObserving = true
            changes.observe { [weak self] in await self?.refresh() }
            Task { await refresh() }
        }

        /// Uncounts `drawer`. Once no drawer has the plugin, stops observing the source and drops
        /// what was read; a read on its way is dropped too.
        func uninstall(from drawer: ObjectIdentifier) {
            installedDrawers.remove(drawer)
            guard installedDrawers.isEmpty, isObserving else { return }
            isObserving = false
            changes.stop()
            latestRead += 1
            pending = .loading
        }

        /// Reads the pending requests again.
        func refresh() async {
            latestRead += 1
            let read = latestRead
            let requests = await client.pendingTaskRequests()
            guard read == latestRead else {
                Self.logger.debug("Dropped a read that a later one overtook")
                return
            }
            Self.logger.debug("Read \(requests.count) pending task requests")
            pending = .loaded(requests)
        }

        /// Submits a request of `kind` for `identifier` that may begin now, then reads the
        /// requests again; a refusal shows on the identifier's row.
        func schedule(_ identifier: String, as kind: BackgroundTaskKind) async {
            schedule = .scheduling(identifier: identifier, kind: kind)
            do {
                try await client.submit(identifier: identifier, kind: kind, earliestBeginDate: now())
                Self.logger.info("Scheduled \(identifier, privacy: .public) as \(kind.title, privacy: .public)")
                schedule = .idle
            } catch {
                Self.logger.error("The scheduler refused \(identifier, privacy: .public): \(error.explanation, privacy: .public)")
                schedule = .failed(identifier: identifier, kind: kind, failure: error)
            }
            await refresh()
        }

        // The cancellations update the list themselves rather than read it again: the scheduler
        // documents nothing of when a cancellation shows in its pending requests, so a read right
        // after could still list what was cancelled. The next read (on becoming active, after a
        // Schedule, on Refresh) shows the scheduler's own.

        func cancel(_ identifier: BackgroundTaskRequest.ID) {
            client.cancel(taskRequestWithIdentifier: identifier)
            change { $0.removeAll { $0.id == identifier } }
        }

        func cancelAll() {
            client.cancelAllTaskRequests()
            change { $0 = [] }
        }

        /// Applies `edit` to what was last read; a read on its way is dropped, as it may predate
        /// the cancellation.
        private func change(_ edit: (inout [BackgroundTaskRequest]) -> Void) {
            guard case var .loaded(requests) = pending else { return }
            latestRead += 1
            edit(&requests)
            pending = .loaded(requests)
        }
    }
#endif
