#if DEBUG
    import Foundation
    import QuartzCore

    /// The production frame source: on every display frame, up to 30 a second, the app's windows
    /// drawn without the drawer (`RecordedWindows`).
    ///
    /// The display link is the event each frame waits for, so nothing polls or sleeps. Drawing
    /// runs on the main actor, where the layer tree lives; a frame the encoder isn't ready for is
    /// dropped by the writer rather than queued.
    @MainActor
    final class DisplayLinkFrameSource: RecordingFrameSource {
        private var link: CADisplayLink?
        #if os(iOS)
            private var touches: TouchObserver?
        #endif

        init() {}

        func start(showsTouches: Bool, frame: @escaping @MainActor (RecordedFrame) -> Void) throws(RecordingFailure) {
            stop()
            guard let windows = RecordedWindows() else { throw .noWindow }
            #if os(iOS)
                let touches = showsTouches ? TouchObserver(windows: windows.windows) : nil
                self.touches = touches
                let target = DisplayLinkTarget { [windows, touches] timestamp in
                    let canvas = windows.windows.first(where: \.isKeyWindow) ?? windows.windows.first
                    let points = canvas.map { touches?.locations(in: $0) ?? [] } ?? []
                    guard let image = windows.render(touches: points) else { return }
                    frame(RecordedFrame(image: image, time: timestamp))
                }
            #else
                // Touch indicators are an iOS feature: a Mac has a pointer, which the frames don't draw.
                _ = showsTouches
                let target = DisplayLinkTarget { [windows] timestamp in
                    guard let image = windows.render(touches: []) else { return }
                    frame(RecordedFrame(image: image, time: timestamp))
                }
            #endif
            guard let link = windows.displayLink(target: target, selector: #selector(DisplayLinkTarget.tick(_:))) else {
                throw .noWindow
            }
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
            link.add(to: .main, forMode: .common)
            self.link = link
        }

        func stop() {
            link?.invalidate()
            link = nil
            #if os(iOS)
                touches?.remove()
                touches = nil
            #endif
        }
    }

    /// The display link's target, which it retains until invalidated: hands each frame's time on.
    @MainActor
    private final class DisplayLinkTarget: NSObject {
        private let handler: @MainActor (TimeInterval) -> Void

        init(handler: @escaping @MainActor (TimeInterval) -> Void) {
            self.handler = handler
        }

        @objc func tick(_ link: CADisplayLink) {
            handler(link.timestamp)
        }
    }
#endif
