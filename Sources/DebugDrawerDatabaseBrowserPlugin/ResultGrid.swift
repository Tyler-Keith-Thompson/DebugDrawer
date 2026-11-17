#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// Rows under their column names, in a well that scrolls sideways when the columns are wider
    /// than the drawer, at its natural height (the drawer scrolls the rest). At most
    /// ``cellLimit`` cells are drawn, and a note says when rows are left out. Selecting a cell
    /// shows its whole value below the grid.
    struct ResultGrid: View {
        let result: ResultSet
        /// The most cells the grid draws.
        static let cellLimit = 2000
        @State private var selected: CellPosition?
        @ScaledMetric(relativeTo: .footnote) private var cellPadding: CGFloat = 6
        let inspection = Inspection<Self>() // from/for ViewInspector.

        /// How many rows are drawn, so no more than ``cellLimit`` cells are.
        var shownRowCount: Int {
            min(result.rows.count, max(1, Self.cellLimit / max(1, result.columns.count)))
        }

        var body: some View {
            VStack(alignment: .leading, spacing: 4) {
                DebugDrawerCodeBlock {
                    ScrollView(.horizontal) {
                        grid
                    }
                }
                ForEach(notes, id: \.self) { note in
                    Text(note)
                        .debugDrawerFont(.secondary)
                        .debugDrawerForegroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let selected, let value = value(at: selected) {
                    detail(of: value, at: selected)
                }
            }
            .onReceive(inspection.notice) { inspection.visit(self, $0) }
        }

        private var grid: some View {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(result.columns.enumerated()), id: \.offset) { _, name in
                        Text(name)
                            .fontWeight(.semibold)
                            .debugDrawerForegroundStyle(.secondary)
                            // One line at any text size: the grid scrolls sideways, and cellText already cut it.
                            .fixedSize(horizontal: true, vertical: false)
                            .padding(.horizontal, cellPadding)
                            .padding(.vertical, cellPadding / 3)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
                Divider()
                ForEach(0 ..< shownRowCount, id: \.self) { row in
                    GridRow {
                        ForEach(0 ..< result.columns.count, id: \.self) { column in
                            cell(at: CellPosition(row: row, column: column))
                        }
                    }
                }
            }
            // A cell is a button that shows its value below; selecting text in it would fight
            // the press.
            .disablingTextSelection()
        }

        private func cell(at position: CellPosition) -> some View {
            let value = value(at: position) ?? .null
            return Button {
                selected = selected == position ? nil : position
            } label: {
                ValueCell(value: value)
                    .padding(.horizontal, cellPadding)
                    .padding(.vertical, cellPadding / 3)
                    .debugDrawerSelected(selected == position)
                    .contentShape(Rectangle())
            }
            .debugDrawerButtonStyle(.plain)
            .help(value.displayText)
            .accessibilityLabel("\(result.columns[position.column]), \(value.displayText)")
            .accessibilityAddTraits(selected == position ? .isSelected : [])
            .accessibilityHint("Shows the whole value below the grid")
        }

        private func detail(of value: SQLiteValue, at position: CellPosition) -> some View {
            VStack(alignment: .leading, spacing: 0) {
                DebugDrawerRow(result.columns[position.column]) {
                    Text("Row \((position.row + 1).formatted()) · \(value.typeName)")
                } accessory: {
                    Button {
                        selected = nil
                    } label: {
                        Label("Close", systemImage: "xmark")
                            .labelStyle(.iconOnly)
                    }
                    .debugDrawerButtonStyle(.borderless)
                    .accessibilityLabel("Close the value of \(result.columns[position.column])")
                }
                DebugDrawerCodeBlock {
                    Text(value.displayText)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }

        /// The notes below the grid: that there are no rows, that some aren't drawn, or that the
        /// statement returned more than were read.
        var notes: [String] {
            var notes: [String] = []
            if result.rows.isEmpty {
                notes.append("No rows.")
            } else if shownRowCount < result.rows.count {
                let shown = "Showing the first \(shownRowCount.formatted()) of \(result.rows.count.formatted()) rows"
                notes.append("\(shown): the grid draws at most \(Self.cellLimit.formatted()) cells.")
            }
            if result.isTruncated {
                notes.append("Only the first \(result.rows.count.formatted()) rows were read.")
            }
            return notes
        }

        private func value(at position: CellPosition) -> SQLiteValue? {
            guard result.rows.indices.contains(position.row), result.rows[position.row].indices.contains(position.column) else { return nil }
            return result.rows[position.row][position.column]
        }
    }

    /// A cell of the grid, by row and column, from 0.
    struct CellPosition: Hashable {
        let row: Int
        let column: Int
    }

    extension View {
        /// Turns text selection off, where the platform has it.
        @ViewBuilder
        fileprivate func disablingTextSelection() -> some View {
            #if os(tvOS) || os(watchOS)
                self
            #else
                textSelection(.disabled)
            #endif
        }
    }
#endif
