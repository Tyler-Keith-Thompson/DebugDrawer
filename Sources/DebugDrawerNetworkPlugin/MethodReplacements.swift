#if DEBUG
    import ObjectiveC
    import os

    // Copied into each plugin that replaces methods (Network, Disk I/O, Location, View Inspector,
    // Leaks, Localization): plugins share no helper target, and these few lines cost less than one.

    /// The Objective-C methods a plugin replaced, each kept with the implementation it replaced, so
    /// uninstalling sets that exact implementation back rather than swapping a second time.
    ///
    /// A method other code has replaced again since (a swizzle made on top of the plugin's) can't
    /// be put back without dropping that code's replacement, which calls the plugin's: it is left
    /// in place, and the plugin's replacement must then call straight through while uninstalled.
    /// A later install replaces only the methods put back, so nothing is replaced twice.
    @MainActor
    final class MethodReplacements {
        /// One replacement: methods changed together, in order, and put back together, in reverse.
        private struct Replacement {
            let changes: [MethodChange]

            /// Whether every method still runs the plugin's implementation.
            var isCurrent: Bool {
                changes.allSatisfy { method_getImplementation($0.method) == $0.replacement }
            }

            func contains(_ method: Method) -> Bool {
                changes.contains { $0.method == method }
            }
        }

        private static let logger = Logger(subsystem: "DebugDrawer", category: "MethodReplacements")

        private var replacements: [Replacement] = []

        /// Whether any method runs the plugin's implementation.
        var isEmpty: Bool {
            replacements.isEmpty
        }

        /// Sets the implementation `make` builds from `method`'s current one; does nothing when
        /// `method` already runs one of the plugin's.
        ///
        /// - Parameters:
        ///   - method: The method to replace.
        ///   - make: Builds the replacement, given the implementation it replaces.
        func replace(_ method: Method, with make: (IMP) -> IMP) {
            guard !replacements.contains(where: { $0.contains(method) }) else { return }
            let original = method_getImplementation(method)
            let replacement = make(original)
            method_setImplementation(method, replacement)
            replacements.append(Replacement(changes: [MethodChange(method: method, original: original, replacement: replacement)]))
        }

        /// Swaps the implementations of `method` and `swapped`, as `method_exchangeImplementations`
        /// does: `method` then runs `swapped`'s code, which calls `swapped`'s selector to run the
        /// original. Does nothing when `method` already runs one of the plugin's.
        func exchange(_ method: Method, with swapped: Method) {
            guard !replacements.contains(where: { $0.contains(method) }) else { return }
            let original = method_getImplementation(method)
            let replacement = method_getImplementation(swapped)
            // `swapped` first: nothing calls its selector until `method` runs the replacement, so
            // no call on another thread meets the replacement calling itself.
            let changes = [
                MethodChange(method: swapped, original: replacement, replacement: original),
                MethodChange(method: method, original: original, replacement: replacement)
            ]
            for change in changes {
                method_setImplementation(change.method, change.replacement)
            }
            replacements.append(Replacement(changes: changes))
        }

        /// Puts back the original implementation of every method that still runs the plugin's,
        /// and leaves the ones other code has replaced again since.
        ///
        /// - Returns: How many replacements were left in place; 0 when every method has its
        ///   original implementation again.
        @discardableResult
        func restore() -> Int {
            var kept: [Replacement] = []
            for replacement in replacements.reversed() {
                guard replacement.isCurrent else {
                    kept.insert(replacement, at: 0)
                    continue
                }
                for change in replacement.changes.reversed() {
                    method_setImplementation(change.method, change.original)
                }
            }
            replacements = kept
            if !kept.isEmpty {
                Self.logger.notice(
                    "\(kept.count, privacy: .public) replaced methods were replaced again by other code; left in place, calling straight through"
                )
            }
            return kept.count
        }
    }

    /// One method's implementation as the plugin set it, and the one it replaced.
    private struct MethodChange {
        let method: Method
        let original: IMP
        let replacement: IMP
    }
#endif
