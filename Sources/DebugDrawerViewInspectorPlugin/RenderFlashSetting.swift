#if DEBUG
    import Combine

    /// Whether tracked views flash their frame when their body is evaluated.
    ///
    /// Apart from `RenderTracker`, so that a flash, which reads this, doesn't redraw each time the
    /// counts are published.
    @MainActor
    final class RenderFlashSetting: ObservableObject {
        /// The setting the plugin's Flash Renders row changes, which every tracked view's flash
        /// reads.
        static let shared = RenderFlashSetting()

        /// Off until the plugin turns it on.
        @Published var isOn = false
    }
#endif
