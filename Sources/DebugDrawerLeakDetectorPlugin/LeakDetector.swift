/// Leaks in the debug drawer: the app's view controllers still alive after their screen was
/// dismissed, and objects that opted in with ``trackLifetime(of:maxCount:)`` alive in greater
/// numbers than their class allows.
///
/// Every decision follows a lifecycle event, never a timer: a view controller's
/// `viewDidDisappear`, the end of a turn of the main run loop, an object's deallocation.
///
/// The type exists in every build, so the calls compile unchanged in release, where they do
/// nothing.
public enum LeakDetector {
    /// Adds the Leaks plugin and watches the app's view controllers from now on: in debug builds
    /// only; in release it does nothing.
    ///
    /// Call it once at startup; calling it again does nothing more, unless the plugin was removed
    /// from the drawer, which puts the original back: then it starts over. It exchanges
    /// `viewDidDisappear` on `UIViewController` (`NSViewController` on macOS) for an
    /// implementation that calls the original, then notes a view controller of the app's own
    /// classes that is being dismissed or removed from its container. At the end of the next
    /// turn of the main run loop, one still alive and still off screen is a suspect: the plugin
    /// lists it by class with a count, raises its badge and posts a toast ("ProfileViewController
    /// is still alive after it was dismissed"). A suspect that deallocates later, or is shown
    /// again, stops being one.
    @MainActor
    public static func install() {
        #if DEBUG
            LeakDetectorInstallation.install()
        #endif
    }

    /// Counts `object` among the live instances of its class until it deallocates; while more than
    /// `maxCount` are alive, the class is a suspect: in debug builds only; in release it does
    /// nothing.
    ///
    /// Call it once per object, usually from its initializer: `LeakDetector.trackLifetime(of:
    /// self)`. Calling it again for the same object changes nothing. It holds no reference to the
    /// object: it attaches an object of its own, whose release tells it when `object` deallocates.
    /// It can be called from any thread, and before ``install()``, which shows what it found. Once
    /// the plugin has been removed from the drawer, it counts nothing until it is installed again.
    ///
    /// - Parameters:
    ///   - object: The object to count.
    ///   - maxCount: How many instances of `object`'s class should be alive at most at once; the
    ///     last value given for a class is the one used. Traps in debug builds unless positive.
    public static func trackLifetime(of object: AnyObject, maxCount: Int = 1) {
        #if DEBUG
            precondition(maxCount > 0, "maxCount must be positive")
            LeakDetectorInstallation.track(object, maxCount: maxCount)
        #endif
    }
}
