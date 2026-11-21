#if DEBUG
    // MARK: - Objects held weakly

    // Copied from core's internal WeakSet, as MethodReplacements is copied into each plugin that
    // swizzles: plugins share no helper target, core's is not plugin contract, and these few lines
    // cost less than either. Only what the grid's probes use is copied (no remove).
    //
    // Swift's own weak references rather than Foundation's weak hash table (weakObjects()): the
    // table reads its entries through Objective-C weak loads, which retain and autorelease, so
    // adding a probe (now and then, as the table rehashes) or listing them (allObjects) left
    // probes in the caller's autorelease pool, alive after their view was removed until the run
    // loop drained it, and refreshOverlays() could still list them (DD-281, as DD-279 found in
    // core). A Swift weak load hands back a strong reference ARC releases at once, so a probe goes
    // the moment its last owner lets go. Linear in the number of probes; an app places a handful.
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
        /// - Complexity: O(*n*), where *n* is the number of objects added and not yet freed.
        mutating func add(_ object: Element) {
            entries.removeAll { $0.object == nil }
            guard !entries.contains(where: { $0.object === object }) else { return }
            entries.append(Entry(object: object))
        }
    }
#endif
