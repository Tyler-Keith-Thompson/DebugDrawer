#if DEBUG
    import ObjectiveC

    /// Where a class's code comes from: the app (and the frameworks it ships), or the system.
    ///
    /// View controllers of the system's own classes (SwiftUI's hosting and presentation
    /// controllers, the system's alerts and pickers) are kept for reuse by their frameworks, so the
    /// leak detector watches the app's classes only.
    enum ClassOrigin: Equatable, Sendable {
        case app
        case system

        /// The origin of the code at `imagePath`, the binary a class is defined in; `nil`, as for
        /// a generic class's specialization made at run time, is the system's, since no screen of
        /// the app's own is told apart by it.
        init(imagePath: String?) {
            guard let imagePath else {
                self = .system
                return
            }
            // The simulator's system frameworks sit under its runtime's root, the device's and the
            // Mac's under /System and /usr/lib.
            let isSystem = imagePath.hasPrefix("/System/") || imagePath.hasPrefix("/usr/lib/") || imagePath.contains("/RuntimeRoot/")
            self = isSystem ? .system : .app
        }

        /// The origin of `type`.
        init(of type: AnyClass) {
            self.init(imagePath: class_getImageName(type).map { String(cString: $0) })
        }
    }
#endif
