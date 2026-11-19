#if DEBUG
    import Combine
    import Foundation

    /// Plays a route through a ``LocationOverride``: each point at its offset in the track divided
    /// by the speed, on the scheduler's clock. ``LocationModel`` holds the one the plugin shows,
    /// which keeps playing while the drawer is closed.
    ///
    /// Each point goes to every manager the simulator tracks, stamped with the moment it is
    /// delivered, so the track's spacing divided by the speed, and carrying the course and speed
    /// the track gives it (``RouteFix``). Pausing keeps the points delivered; playing again waits
    /// the whole gap to the next one. A speed changed while playing applies from the gap after the
    /// last point delivered.
    @MainActor
    final class RoutePlayer: ObservableObject {
        /// The routes to choose from: the samples, then the file imported last, if any.
        @Published private(set) var routes: [Route]
        /// The route that plays.
        @Published private(set) var route: Route
        @Published private(set) var playback: RoutePlayback = .stopped
        /// Why the file imported last couldn't be played, or nil.
        @Published private(set) var importFailure: GPXError?
        @Published var speed: PlaybackSpeed = .times1 {
            didSet {
                if case let .playing(delivered) = playback { scheduleNext(after: delivered) }
            }
        }

        private let scheduler: any PlaybackScheduler
        private let simulator: any LocationOverride
        private var pending: AnyCancellable?

        /// - Parameters:
        ///   - routes: The routes to choose from, the first chosen; at least one.
        ///   - scheduler: The clock playback runs on.
        ///   - simulator: Where each point is delivered.
        init(routes: [Route] = Route.samples, scheduler: any PlaybackScheduler, simulator: any LocationOverride) {
            precondition(!routes.isEmpty, "A route player needs a route to play")
            self.routes = routes
            route = routes[0]
            self.scheduler = scheduler
            self.simulator = simulator
        }

        /// Stops playback and chooses another of ``routes``.
        func select(_ id: Route.ID) {
            guard let chosen = routes.first(where: { $0.id == id }), chosen != route else { return }
            stop()
            importFailure = nil
            route = chosen
        }

        /// Stops playback and chooses the route of an imported file, or shows why it can't be played.
        ///
        /// - Parameters:
        ///   - result: The file's track, or why it couldn't be read.
        ///   - url: The file, which names the route.
        func importFile(_ result: Result<GPXTrack, GPXError>, from url: URL) {
            switch result {
            case let .success(track):
                stop()
                let imported = Route(imported: track, from: url)
                routes = routes.filter { !$0.id.hasPrefix("imported:") } + [imported]
                route = imported
                importFailure = nil
            case let .failure(error):
                importFailure = error
            }
        }

        /// Starts from the first point, or carries on after a pause.
        func play() {
            switch playback {
            case .stopped, .finished:
                deliver(0)
            case let .paused(delivered):
                playback = .playing(delivered: delivered)
                scheduleNext(after: delivered)
            case .playing:
                break
            }
        }

        /// Holds the last point delivered in effect until Play.
        func pause() {
            guard case let .playing(delivered) = playback else { return }
            pending = nil
            playback = .paused(delivered: delivered)
        }

        /// Ends playback; managers go back to the fixed coordinate, if one is set.
        func stop() {
            pending = nil
            guard playback != .stopped else { return }
            playback = .stopped
            simulator.endRoute()
        }

        private func deliver(_ index: Int) {
            let fixes = route.fixes
            simulator.deliverRoute(fixes[index].location(at: scheduler.now))
            let delivered = index + 1
            if delivered == fixes.count {
                pending = nil
                playback = .finished
            } else {
                playback = .playing(delivered: delivered)
                scheduleNext(after: delivered)
            }
        }

        /// Schedules the point after the `delivered` first ones, its gap from the last divided by
        /// the speed.
        private func scheduleNext(after delivered: Int) {
            let fixes = route.fixes
            let gap = fixes[delivered].offset - fixes[delivered - 1].offset
            pending = scheduler.schedule(after: gap / speed.rawValue) { [weak self] in
                self?.deliver(delivered)
            }
        }
    }
#endif
