#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// The process's threads, busiest first, each with its name and CPU. Collapsed, it shows the
    /// busiest few that are using any CPU, and folds the idle rest into a count; Show All lists
    /// every thread.
    struct ThreadsSection: View {
        /// The threads, busiest first.
        let threads: [ThreadCPU]
        @State var showsAll = false
        let inspection = Inspection<Self>()

        /// How many busy threads the collapsed list shows.
        static let collapsedLimit = 8

        var body: some View {
            DebugDrawerSection("Threads") {
                ForEach(visibleThreads) { ThreadCPURow(thread: $0) }
                if !showsAll, hiddenCount > 0 {
                    Text(hiddenSummary)
                        .debugDrawerFont(.secondary)
                        .debugDrawerForegroundStyle(.secondary)
                        .debugDrawerRowPadding()
                }
                if hiddenCount > 0 || showsAll {
                    Button(showsAll ? "Show Busiest" : "Show All \(threads.count)") {
                        showsAll.toggle()
                    }
                    .debugDrawerButtonStyle(.borderless)
                    .debugDrawerRowPadding()
                    .accessibilityLabel(showsAll ? "Show the busiest threads only" : "Show all \(threads.count) threads")
                }
            }
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
        }

        /// Every thread, or the busiest few that use any CPU.
        var visibleThreads: [ThreadCPU] {
            showsAll ? threads : Array(threads.filter { $0.cpuUsage > 0 }.prefix(Self.collapsedLimit))
        }

        private var hiddenCount: Int {
            threads.count - visibleThreads.count
        }

        /// "21 more threads, 18 idle": how many the collapsed list leaves out, and how many of
        /// those use no CPU; "All 23 threads idle" when none is busy.
        private var hiddenSummary: String {
            let idle = threads.count(where: { $0.cpuUsage == 0 })
            if visibleThreads.isEmpty { return idle == 1 ? "1 thread, idle" : "All \(idle) threads idle" }
            let more = hiddenCount == 1 ? "1 more thread" : "\(hiddenCount) more threads"
            return idle > 0 ? "\(more), \(idle) idle" : more
        }
    }

    /// A thread's name in monospaced type and its share of a core right-aligned on one line. At
    /// accessibility text sizes the name wraps and the share moves under it.
    struct ThreadCPURow: View {
        let thread: ThreadCPU
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

        var body: some View {
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            layout {
                Text(thread.name)
                    .debugDrawerFont(.code)
                    // One line, cut in the middle: queue-style names share long prefixes
                    // ("com.apple.…"), so both ends show. At accessibility sizes it wraps whole.
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .truncationMode(.middle)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(thread.cpuUsage, format: .percent.precision(.fractionLength(1)))
                    .debugDrawerFont(.value)
                    .debugDrawerForegroundStyle(thread.cpuUsage > 0 ? .primary : .tertiary)
            }
            .debugDrawerRowPadding()
            .accessibilityElement(children: .combine)
        }
    }
#endif
