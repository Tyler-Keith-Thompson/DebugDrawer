#if DEBUG
    import CoreGraphics
    import Foundation
    import ImageIO
    import UniformTypeIdentifiers

    /// What a file's contents show as, told from its bytes rather than its extension.
    enum FilePreview: Hashable, Sendable {
        /// UTF-8 text.
        case text(PreviewText)
        /// JSON, pretty-printed with its keys sorted.
        case json(PreviewText)
        /// A property list, binary or XML, shown as XML.
        case propertyList(PreviewText, PropertyListFormat)
        /// An image ImageIO can decode.
        case image(PreviewImage)
        /// A SQLite database, which has no preview here.
        case sqlite
        /// A file with nothing in it.
        case empty
        /// Bytes that are none of the above.
        case binary

        /// The kind of property list.
        enum PropertyListFormat: Hashable, Sendable {
            case binary
            case xml
        }

        /// How much of a file is read for a preview: 1 MiB.
        static let readLimit = 1 << 20
        /// How much of an image is read for its thumbnail: 64 MiB.
        static let imageReadLimit = 64 << 20

        /// The preview of `data`, the first bytes of a file.
        ///
        /// - Parameters:
        ///   - data: The file's bytes, or its first bytes.
        ///   - isTruncated: Whether the file goes on past `data`. A cut-off JSON file or property
        ///     list can't be parsed, so it shows as the text it begins with.
        init(data: Data, isTruncated: Bool) {
            if data.isEmpty {
                self = .empty
            } else if data.starts(with: Self.sqliteHeader) {
                self = .sqlite
            } else if data.starts(with: Self.binaryPropertyListHeader) {
                self = Self.propertyList(data, format: .binary) ?? .binary
            } else if let image = PreviewImage(data: data) {
                self = .image(image)
            } else if let text = PreviewText(data: data, isTruncated: isTruncated) {
                self = Self.structured(data, text: text) ?? .text(text)
            } else {
                self = .binary
            }
        }

        /// Whether `data` begins as an image ImageIO can decode, so the rest of a long one is
        /// worth reading.
        static func isImage(_ data: Data) -> Bool {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return false }
            return CGImageSourceGetType(source) != nil
        }

        /// What the file is, in a few words: "JSON", "Property list (binary)", "PNG image".
        var kindTitle: String {
            switch self {
            case .text: "Text"
            case .json: "JSON"
            case .propertyList(_, .binary): "Property list (binary)"
            case .propertyList(_, .xml): "Property list (XML)"
            case let .image(image): "\(image.typeName) image"
            case .sqlite: "SQLite database"
            case .empty: "Empty"
            case .binary: "Binary"
            }
        }

        /// The text it shows, for a preview that is text.
        var text: PreviewText? {
            switch self {
            case let .text(text), let .json(text), let .propertyList(text, _): text
            case .image, .sqlite, .empty, .binary: nil
            }
        }

        private static let sqliteHeader = Data("SQLite format 3\0".utf8)
        private static let binaryPropertyListHeader = Data("bplist".utf8)

        /// JSON or an XML property list, when the text is one that parses.
        private static func structured(_ data: Data, text: PreviewText) -> FilePreview? {
            guard !text.isTruncated, let first = text.lines.lazy.flatMap({ $0 }).first(where: { !$0.isWhitespace }) else { return nil }
            switch first {
            case "{", "[":
                return json(data)
            case "<":
                return text.lines.prefix(4).joined().contains("<plist") ? propertyList(data, format: .xml) : nil
            default:
                return nil
            }
        }

        private static func json(_ data: Data) -> FilePreview? {
            guard let object = try? JSONSerialization.jsonObject(with: data),
                  let pretty = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            else { return nil }
            return PreviewText(data: pretty, isTruncated: false).map(FilePreview.json)
        }

        private static func propertyList(_ data: Data, format: PropertyListFormat) -> FilePreview? {
            guard let object = try? PropertyListSerialization.propertyList(from: data, format: nil),
                  let xml = try? PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0),
                  let text = PreviewText(data: xml, isTruncated: false)
            else { return nil }
            return .propertyList(text, format)
        }
    }

    /// A preview's text in lines, so a long file is drawn a screenful at a time.
    struct PreviewText: Hashable, Sendable {
        /// The lines, none longer than ``maxLineLength``: a longer one is split, so a minified file
        /// of one long line still draws a line at a time.
        let lines: [String]
        /// Whether the file goes on past the text.
        let isTruncated: Bool

        /// The longest a line is drawn in one piece, in characters.
        static let maxLineLength = 1_000

        /// The text of `data` as UTF-8, or `nil` when it isn't text: it doesn't decode, or holds a
        /// NUL. A truncated file may end inside a character, so up to three bytes are dropped from
        /// its end to decode it.
        init?(data: Data, isTruncated: Bool) {
            guard !data.contains(0) else { return nil }
            let candidates = isTruncated ? (0 ... min(3, data.count - 1)).map { data.dropLast($0) } : [data[...]]
            guard let string = candidates.lazy.compactMap({ String(bytes: $0, encoding: .utf8) }).first else { return nil }
            // By character, so "\r\n", one character, ends a line too. A newline that ends the
            // text ends its last line rather than starting an empty one.
            var split = string.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
            if split.count > 1, split.last?.isEmpty == true {
                split.removeLast()
            }
            lines = split.flatMap(Self.pieces(of:))
            self.string = string
            self.isTruncated = isTruncated
        }

        init(lines: [String], isTruncated: Bool = false) {
            self.lines = lines
            string = lines.joined(separator: "\n")
            self.isTruncated = isTruncated
        }

        /// The text as it was read, as Copy Text copies it.
        let string: String

        /// The line in pieces of at most ``maxLineLength`` characters, walked once: an empty line
        /// is one empty piece.
        private static func pieces(of line: Substring) -> [String] {
            var pieces: [String] = []
            var lower = line.startIndex
            repeat {
                let upper = line.index(lower, offsetBy: maxLineLength, limitedBy: line.endIndex) ?? line.endIndex
                pieces.append(String(line[lower ..< upper]))
                lower = upper
            } while lower < line.endIndex
            return pieces
        }
    }

    /// An image's thumbnail, made by ImageIO without decoding the image at full size.
    struct PreviewImage: Hashable, Sendable {
        let thumbnail: CGImage
        let pixelWidth: Int
        let pixelHeight: Int
        /// Its format's usual extension, capitalized: "PNG", "JPEG".
        let typeName: String

        /// The longest side of a thumbnail, in pixels.
        static let thumbnailSize = 640

        /// The thumbnail of the image in `data`, or `nil` when ImageIO can't decode one.
        init?(data: Data) {
            let thumbnailOptions: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceThumbnailMaxPixelSize: Self.thumbnailSize
            ]
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let type = CGImageSourceGetType(source),
                  let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, thumbnailOptions as CFDictionary)
            else { return nil }
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
            self.thumbnail = thumbnail
            pixelWidth = properties?[kCGImagePropertyPixelWidth] as? Int ?? thumbnail.width
            pixelHeight = properties?[kCGImagePropertyPixelHeight] as? Int ?? thumbnail.height
            typeName = (UTType(type as String)?.preferredFilenameExtension ?? "image").uppercased()
        }
    }
#endif
