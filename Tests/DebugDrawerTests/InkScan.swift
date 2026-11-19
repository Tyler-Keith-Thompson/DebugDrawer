import Testing

/// A bitmap reduced to where it is inked, the first row at the top, and the scan
/// `DrawerRowIconAlignmentTests` reads a row's icon and title from: the icon is the leftmost run of
/// inked columns, the title is what follows it, and each one's lines are its runs of inked rows.
///
/// The scan reports a bitmap it can't read, such as one with no gap after the icon, through
/// `#require`, so a surprising rendering fails the test that drew it instead of trapping on a range
/// or an index and taking the whole test process down.
struct InkBitmap {
    let width: Int
    let height: Int
    /// Row by row, `width` values per row.
    let ink: [Bool]

    init(width: Int, height: Int, ink: [Bool]) {
        precondition(width >= 0 && height >= 0 && ink.count == width * height, "ink holds width × height values")
        self.width = width
        self.height = height
        self.ink = ink
    }

    /// One string per row, `#` for ink and anything else for background.
    init(_ rows: [String]) {
        let width = rows.first?.count ?? 0
        precondition(rows.allSatisfy { $0.count == width }, "every row is as wide as the first")
        self.init(width: width, height: rows.count, ink: rows.flatMap { $0.map { $0 == "#" } })
    }

    func inked(_ column: Int, _ row: Int) -> Bool {
        ink[row * width + column]
    }

    /// The icon's and the title's runs of inked rows, top first. `scale` is pixels per point: the
    /// icon and the title are at least the row's 8-point spacing apart, and a symbol's own gaps are
    /// narrower than 4 points.
    func iconAndTitleLines(scale: Int) throws -> (icon: [ClosedRange<Int>], title: [ClosedRange<Int>]) {
        let columns = Self.runs((0 ..< width).map { column in (0 ..< height).contains { row in inked(column, row) } }, gap: 4 * scale)
        let iconColumns = try #require(columns.first, "the bitmap (\(width) × \(height) px) has no ink")
        // The title's first letters, past the icon: narrow enough to miss an accessory at the
        // trailing edge, and above one stacked below the title.
        let titleStart = iconColumns.upperBound + 4 * scale
        try #require(
            titleStart < width,
            """
            no title after the icon: the first run of inked columns, \(iconColumns), reaches within \
            \(4 * scale) px of the bitmap's right edge (\(width) px wide); rows inked edge to edge: \
            \(Self.runs((0 ..< height).map { row in (0 ..< width).allSatisfy { inked($0, row) } }, gap: 1))
            """
        )
        let titleColumns = titleStart ... min(width - 1, titleStart + 16 * scale)
        let iconLines = Self.runs((0 ..< height).map { row in iconColumns.contains { inked($0, row) } }, gap: 2 * scale)
        let titleLines = Self.runs((0 ..< height).map { row in titleColumns.contains { inked($0, row) } }, gap: 2 * scale)
        try #require(!iconLines.isEmpty)
        try #require(!titleLines.isEmpty, "no ink in columns \(titleColumns), where the title starts")
        return (iconLines, titleLines)
    }

    /// The runs of true values, merging gaps shorter than `gap` values, which lie inside a glyph.
    static func runs(_ marks: [Bool], gap: Int) -> [ClosedRange<Int>] {
        var result: [ClosedRange<Int>] = []
        for index in marks.indices where marks[index] {
            if let last = result.last, index - last.upperBound <= gap {
                result[result.count - 1] = last.lowerBound ... index
            } else {
                result.append(index ... index)
            }
        }
        return result
    }
}
