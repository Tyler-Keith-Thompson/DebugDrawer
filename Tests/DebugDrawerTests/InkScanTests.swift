import Testing

// InkBitmap is the scan DrawerRowIconAlignmentTests reads a drawn row with; these feed it bitmaps
// made by hand, at 1 pixel per point, so a rendering it can't read fails a test instead of trapping.
@Suite
struct InkScanTests {
    @Test("An icon, a gap and a title give the icon's and the title's lines")
    func iconAndTitle() throws {
        let bitmap = InkBitmap([
            "............",
            "##.....###..",
            "##.....###..",
            "............"
        ])

        let lines = try bitmap.iconAndTitleLines(scale: 1)

        #expect(lines.icon == [1 ... 2])
        #expect(lines.title == [1 ... 2])
    }

    @Test("A bitmap inked edge to edge, with no gap after the icon, fails through #require rather than trapping")
    func noGapAfterIcon() throws {
        // A row inked across the whole width, as a partly clear last row of pixels reads, joins
        // every column into one run, so the title would start past the right edge.
        let bitmap = InkBitmap([
            "............",
            "##.....###..",
            "############"
        ])

        try withKnownIssue {
            _ = try bitmap.iconAndTitleLines(scale: 1)
        } matching: { issue in
            issue.comments.contains { $0.rawValue.contains("no title after the icon") }
        }
    }

    @Test("An icon ending within the gap of the right edge fails through #require rather than trapping")
    func iconAtRightEdge() throws {
        let bitmap = InkBitmap([
            "........##",
            "........##"
        ])

        try withKnownIssue {
            _ = try bitmap.iconAndTitleLines(scale: 1)
        } matching: { issue in
            issue.comments.contains { $0.rawValue.contains("no title after the icon") }
        }
    }

    @Test("An icon with nothing in the columns after it fails through #require")
    func noTitleInk() throws {
        let bitmap = InkBitmap([
            "##..........",
            "##.........."
        ])

        try withKnownIssue {
            _ = try bitmap.iconAndTitleLines(scale: 1)
        } matching: { issue in
            issue.comments.contains { $0.rawValue.contains("where the title starts") }
        }
    }

    @Test("A blank bitmap fails through #require")
    func blank() throws {
        try withKnownIssue {
            _ = try InkBitmap(["....", "...."]).iconAndTitleLines(scale: 1)
        } matching: { issue in
            issue.comments.contains { $0.rawValue.contains("has no ink") }
        }
    }
}
