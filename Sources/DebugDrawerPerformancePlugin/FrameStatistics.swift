#if DEBUG
    import Foundation

    /// The frame rate and the frames dropped over a run of display-link callbacks.
    ///
    /// A display link on the main run loop calls back once per frame while the main thread is free
    /// and not at all while it is blocked, so a block shows as a gap between two timestamps. Each
    /// gap counts the frame periods it spans, less the one frame it delivers, as dropped.
    struct FrameStatistics: Equatable {
        /// The callbacks per second over the run, rounded; 0 for fewer than two timestamps.
        let framesPerSecond: Int
        /// The frame periods the run's gaps skipped.
        let droppedFrames: Int

        /// The statistics of `timestamps`, one per callback, oldest first.
        ///
        /// - Parameters:
        ///   - timestamps: When each callback's frame was displayed, in seconds, oldest first.
        ///   - frameDuration: The display link's frame period, in seconds.
        /// - Complexity: O(*n*), where *n* is the number of timestamps.
        init(timestamps: [TimeInterval], frameDuration: TimeInterval) {
            guard let first = timestamps.first, let last = timestamps.last, last > first else {
                self.init(framesPerSecond: 0, droppedFrames: 0)
                return
            }
            let rate = Double(timestamps.count - 1) / (last - first)
            self.init(
                framesPerSecond: Int(rate.rounded()),
                droppedFrames: frameDuration > 0 ? timestamps.droppedFrames(frameDuration: frameDuration) : 0
            )
        }

        init(framesPerSecond: Int, droppedFrames: Int) {
            self.framesPerSecond = framesPerSecond
            self.droppedFrames = droppedFrames
        }
    }

    extension [TimeInterval] {
        /// The frame periods skipped between consecutive timestamps: a gap of *n* periods,
        /// rounded to absorb the display's jitter, delivers one frame and drops *n* − 1.
        fileprivate func droppedFrames(frameDuration: TimeInterval) -> Int {
            zip(self, dropFirst()).reduce(0) { dropped, pair in
                let periods = Int(((pair.1 - pair.0) / frameDuration).rounded())
                return dropped + Swift.max(periods - 1, 0)
            }
        }
    }
#endif
