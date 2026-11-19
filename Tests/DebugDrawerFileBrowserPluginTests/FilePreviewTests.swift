#if DEBUG
    @testable import DebugDrawerFileBrowserPlugin
    import Foundation
    import Testing

    @Suite
    struct FilePreviewTests {
        @Test("UTF-8 text previews as its lines")
        func text() {
            let data = Data("first line\r\nsecond — line\n\nlast".utf8)
            let expectedLines = ["first line", "second — line", "", "last"]

            let actual = FilePreview(data: data, isTruncated: false)

            #expect(actual.text?.lines == expectedLines)
            #expect(actual.text?.string == "first line\r\nsecond — line\n\nlast")
            #expect(actual.kindTitle == "Text")
        }

        @Test("JSON previews pretty-printed, its keys sorted and its slashes unescaped")
        func json() {
            let data = Data(#"{"name":"Ada","tags":["a/b"],"age":36}"#.utf8)
            let expectedLines = ["{", #"  "age" : 36,"#, #"  "name" : "Ada","#, #"  "tags" : ["#, #"    "a/b""#, "  ]", "}"]

            let actual = FilePreview(data: data, isTruncated: false)

            #expect(actual == .json(PreviewText(lines: expectedLines)))
            #expect(actual.kindTitle == "JSON")
        }

        @Test("An XML property list previews as XML")
        func xmlPropertyList() throws {
            let data = try PropertyListSerialization.data(fromPropertyList: ["enabled": true, "count": 3], format: .xml, options: 0)

            let actual = FilePreview(data: data, isTruncated: false)

            let text = try #require(actual.text)
            #expect(actual.kindTitle == "Property list (XML)")
            #expect(text.lines.contains("\t<key>count</key>"))
            #expect(text.lines.contains("\t<true/>"))
            // The newline that ends the file starts no empty line.
            #expect(text.lines.last == "</plist>")
        }

        @Test("A binary property list previews as XML")
        func binaryPropertyList() throws {
            let data = try PropertyListSerialization.data(fromPropertyList: ["name": "Ada"], format: .binary, options: 0)

            let actual = FilePreview(data: data, isTruncated: false)

            let text = try #require(actual.text)
            #expect(actual.kindTitle == "Property list (binary)")
            #expect(text.lines.contains("\t<key>name</key>"))
            #expect(text.lines.contains("\t<string>Ada</string>"))
        }

        @Test("A PNG previews as its thumbnail, with its pixel size and format")
        func png() throws {
            let png = "iVBORw0KGgoAAAANSUhEUgAAAAQAAAADCAIAAAA7ljmRAAAAEElEQVR4nGP4z8AARww4OQD1MQv1NXv7ggAAAABJRU5ErkJggg=="
            let data = try #require(Data(base64Encoded: png))

            let actual = FilePreview(data: data, isTruncated: false)

            guard case let .image(image) = actual else {
                Issue.record("Expected an image, got \(actual)")
                return
            }
            #expect(image.pixelWidth == 4)
            #expect(image.pixelHeight == 3)
            #expect(image.typeName == "PNG")
            #expect(actual.kindTitle == "PNG image")
        }

        @Test("A SQLite file is told by its header and has no preview")
        func sqlite() {
            let data = Data("SQLite format 3\0".utf8) + Data(repeating: 0, count: 84)

            let actual = FilePreview(data: data, isTruncated: false)

            #expect(actual == .sqlite)
            #expect(actual.text == nil)
        }

        @Test("An empty file, and bytes that are no text, have no preview")
        func emptyAndBinary() {
            let binary = Data([0xFF, 0xFE, 0x00, 0x01, 0x02])

            #expect(FilePreview(data: Data(), isTruncated: false) == .empty)
            #expect(FilePreview(data: binary, isTruncated: false) == .binary)
            #expect(FilePreview(data: Data([0xC3, 0x28]), isTruncated: false) == .binary)
        }

        @Test("JSON cut short can't be parsed, so it previews as the text it begins with, marked as cut short")
        func truncatedJSON() {
            let data = Data(#"{"name": "Ad"#.utf8)

            let actual = FilePreview(data: data, isTruncated: true)

            #expect(actual == .text(PreviewText(lines: [#"{"name": "Ad"#], isTruncated: true)))
        }

        @Test("Text cut inside a character drops the partial character")
        func truncatedInsideCharacter() {
            let whole = Data("café".utf8)
            let cut = whole.dropLast()

            let actual = FilePreview(data: Data(cut), isTruncated: true)

            #expect(actual == .text(PreviewText(lines: ["caf"], isTruncated: true)))
        }

        @Test("A line longer than the limit is split into pieces of at most the limit, and nothing is lost")
        func longLine() throws {
            let line = String(repeating: "x", count: PreviewText.maxLineLength * 2 + 5)

            let actual = try #require(PreviewText(data: Data(line.utf8), isTruncated: false))

            #expect(actual.lines.map(\.count) == [PreviewText.maxLineLength, PreviewText.maxLineLength, 5])
            #expect(actual.string == line)
        }

        @Test("A file over the read limit is read up to it and marked as cut short")
        func readLimit() async throws {
            let fileSystem = FakeFileSystem(files: ["/app/Documents/long.txt": Data(repeating: UInt8(ascii: "a"), count: FilePreview.readLimit + 10)])
            let item = try await fileSystem.item(at: URL(filePath: "/app/Documents/long.txt"))

            let actual = try await FilePreview.reading(item, from: fileSystem)

            let text = try #require(actual.text)
            #expect(text.isTruncated)
            #expect(text.string.count == FilePreview.readLimit)
        }
    }
#endif
