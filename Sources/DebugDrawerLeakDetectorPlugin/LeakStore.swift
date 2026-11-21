#if DEBUG
    import Combine
    import DebugDrawer
    import Foundation

    /// The suspects the drawer shows, and the classes the developer chose to ignore.
    ///
    /// In memory only: a suspect is about the objects of this run. Main-actor isolated, like the
    /// drawer that shows and edits it.
    @MainActor
    final class LeakStore: ObservableObject {
        /// Every suspect, ignored ones too, the most recently flagged first.
        @Published private(set) var suspects: [LeakSuspect] = []
        /// The classes, by qualified name, whose suspects aren't shown, counted or toasted.
        @Published private(set) var ignored: Set<String> = []

        private let onVisibleCountChange: @MainActor (Int) -> Void
        /// The plugin's badge, counting the suspects not ignored in each drawer that installed the
        /// plugin over this store.
        let badge = DebugDrawerPluginBadge(pluginID: LeakDetectorPlugin.pluginID)

        /// - Parameter onVisibleCountChange: Called with the number of suspects not ignored
        ///   whenever it may have changed, after ``badge`` shows it.
        init(onVisibleCountChange: @escaping @MainActor (Int) -> Void = { _ in }) {
            self.onVisibleCountChange = onVisibleCountChange
        }

        /// The suspects whose class isn't ignored, the most recently flagged first.
        var visibleSuspects: [LeakSuspect] {
            suspects.filter { !isIgnored($0) }
        }

        /// How many suspects are hidden because their class is ignored.
        var ignoredSuspectCount: Int {
            suspects.count(where: isIgnored)
        }

        /// Whether `suspect`'s class is ignored.
        func isIgnored(_ suspect: LeakSuspect) -> Bool {
            ignored.contains(suspect.type.qualifiedName)
        }

        /// Shows `newSuspects` in place of the ones before.
        func update(_ newSuspects: [LeakSuspect]) {
            suspects = newSuspects
            visibleCountDidChange()
        }

        /// Stops showing, counting and toasting `suspect`'s class, for this run.
        func ignore(_ suspect: LeakSuspect) {
            ignored.insert(suspect.type.qualifiedName)
            visibleCountDidChange()
        }

        /// Shows every ignored class's suspects again.
        func stopIgnoring() {
            ignored = []
            visibleCountDidChange()
        }

        private func visibleCountDidChange() {
            let count = visibleSuspects.count
            badge.update(count)
            onVisibleCountChange(count)
        }
    }
#endif
