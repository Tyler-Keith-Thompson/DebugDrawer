#if DEBUG
    #if os(macOS)
        import AppKit
    #elseif os(iOS)
        import UIKit
    #endif
    import Combine
    import QuartzCore

    /// The production sampler: a display link on the main run loop for the frames and a 1 s timer
    /// on it for the ticks.
    ///
    /// The display link calls back only when the main run loop turns, so a blocked main thread
    /// shows as a gap in the timestamps (``FrameStatistics``), and every callback runs on the main
    /// actor.
    @MainActor
    final class DisplayLinkSampler: PerformanceSampler {
        /// The frames' display link while sampling; `nil` once stopped.
        private(set) var displayLink: CADisplayLink?
        /// The 1 s timer's subscription while sampling; `nil` once stopped.
        private(set) var timer: AnyCancellable?

        func start(
            frame: @escaping @MainActor (_ timestamp: TimeInterval, _ frameDuration: TimeInterval) -> Void,
            tick: @escaping @MainActor () -> Void
        ) {
            stop()
            timer = Timer.publish(every: 1, on: .main, in: .common)
                .autoconnect()
                .sink { _ in tick() }
            // The link retains its target, so the target is a small object of its own rather than
            // the sampler, which would then never be released.
            let target = DisplayLinkTarget { link in frame(link.timestamp, link.targetTimestamp - link.timestamp) }
            #if os(macOS)
                // NSScreen's link (macOS 14) follows that screen's refresh; CVDisplayLink would
                // call back on its own thread at the display rate whether or not the main thread
                // was free.
                guard let screen = NSScreen.main else { return }
                let link = screen.displayLink(target: target, selector: #selector(DisplayLinkTarget.step(_:)))
            #else
                let link = CADisplayLink(target: target, selector: #selector(DisplayLinkTarget.step(_:)))
                // 60 Hz is fine enough to see a hitch, and a ProMotion display needn't stay at
                // 120 Hz for the drawer's sake.
                link.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 60, preferred: 60)
            #endif
            link.add(to: .main, forMode: .common)
            displayLink = link
        }

        func stop() {
            timer?.cancel()
            timer = nil
            displayLink?.invalidate()
            displayLink = nil
        }
    }

    /// The display link's target, which hands each callback's link to a closure.
    @MainActor
    private final class DisplayLinkTarget: NSObject {
        private let frame: @MainActor (CADisplayLink) -> Void

        init(frame: @escaping @MainActor (CADisplayLink) -> Void) {
            self.frame = frame
        }

        @objc func step(_ link: CADisplayLink) {
            frame(link)
        }
    }
#endif
