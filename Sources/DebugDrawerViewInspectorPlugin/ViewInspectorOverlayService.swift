#if DEBUG
    import Combine

    /// The View Inspector's work in the app's live windows: the overlay windows its borders, grid
    /// and click indicators are drawn in, and the slowed animations.
    ///
    /// The windows, views and layers stay behind it, so the model that drives it holds values
    /// only. ``ViewBorderController`` is the one the plugin uses; a test passes one that records
    /// the settings.
    @MainActor
    protocol ViewInspectorOverlayService: ObservableObject where ObjectWillChangePublisher == ObservableObjectPublisher {
        /// The switches, as a value; setting it changes only what differs.
        var overlaySettings: ViewInspectorOverlaySettings { get set }

        /// Starts what the switches need from the app as a drawer installs the plugin: on iOS, the
        /// swap of the window class's `sendEvent(_:)` that lets click indicators show touches.
        func install()

        /// Turns every overlay and the slowed animations off and puts back what ``install()``
        /// changed. The grid's spacing, color and opacity stay as set.
        func uninstall()
    }
#endif
