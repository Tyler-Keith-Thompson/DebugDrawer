#if DEBUG
    // MARK: - Objects held weakly

    // Swift's own weak references rather than NSHashTable.weakObjects(): the table reads its
    // entries through Objective-C weak loads, which retain and autorelease, so adding a drawer
    // (now and then, as the table rehashes) or listing them (allObjects) left drawers in the
    // caller's autorelease pool, alive after their last owner let go until the run loop drained
    // it (DD-279). A Swift weak load hands back a strong reference ARC releases at once, so a
    // drawer goes the moment its last owner lets go. Rejected: an autoreleasepool around each
    // table call, which relies on what the table happens to autorelease today. Linear in the
    // number of objects; a set holds a handful of drawers.
    /// Objects held weakly, each once, in the order they were added; one that is freed leaves.
    struct WeakSet<Element: AnyObject> {
        /// One object, held weakly.
        private struct Entry {
            weak var object: Element?
        }

        private var entries: [Entry] = []

        /// The objects not yet freed, in the order they were added.
        var allObjects: [Element] {
            entries.compactMap(\.object)
        }

        /// Adds `object`, unless it is already in the set.
        ///
        /// - Parameter object: The object to hold weakly.
        /// - Complexity: O(*n*), where *n* is the number of objects added and not yet removed.
        mutating func add(_ object: Element) {
            entries.removeAll { $0.object == nil }
            guard !entries.contains(where: { $0.object === object }) else { return }
            entries.append(Entry(object: object))
        }

        /// Removes `object`, if it is in the set.
        ///
        /// - Parameter object: The object to let go of.
        /// - Complexity: O(*n*), where *n* is the number of objects added and not yet removed.
        mutating func remove(_ object: Element) {
            entries.removeAll { $0.object == nil || $0.object === object }
        }
    }
#endif
