import Foundation

/// The files of a bug report, in the order they were added: plain text, JSON, HAR and PNG, each
/// of which opens without DebugDrawer.
///
/// A ``DebugDrawerReportContributor`` adds its files to the report it is handed; the drawer puts
/// them in a folder named after the plugin's title. A name is made safe for a file system (`/`,
/// `\` and `:` become `-`), given its kind's extension when it lacks one, and made unique: a
/// second `console.txt` is `console-2.txt`.
public struct DebugDrawerReport: Equatable, Sendable {
    /// What a file holds, which decides its extension.
    public enum Kind: Equatable, Sendable, CaseIterable {
        /// UTF-8 text, `.txt`.
        case text
        /// JSON, `.json`.
        case json
        /// An HTTP Archive (HAR 1.2, which is JSON), `.har`.
        case har
        /// A PNG image, `.png`.
        case png

        /// The extension a file of this kind ends in, without the dot.
        public var fileExtension: String {
            switch self {
            case .text: "txt"
            case .json: "json"
            case .har: "har"
            case .png: "png"
            }
        }
    }

    /// One file of the report.
    public struct File: Equatable, Sendable {
        /// The folder the file sits in, the contributing plugin's title; nil at the report's root.
        public let folder: String?
        /// The file's name, extension included.
        public let name: String
        /// What the file holds.
        public let kind: Kind
        /// The file's contents.
        public let data: Data

        /// The file's path inside the report: `folder/name`, or `name` at the root.
        public var path: String {
            folder.map { "\($0)/\(name)" } ?? name
        }
    }

    /// Thrown by ``add(json:named:)`` when the value can't be encoded as JSON.
    public struct JSONEncodingFailed: Error, Equatable {}

    /// The files, in the order they were added.
    public private(set) var files: [File] = []

    /// An empty report.
    public init() {}

    /// Adds `text` as UTF-8 in a `.txt` file.
    public mutating func add(text: String, named name: String) {
        append(Data(text.utf8), named: name, kind: .text)
    }

    /// Adds `value` as pretty-printed JSON with sorted keys and ISO 8601 dates, in a `.json` file.
    ///
    /// - Throws: ``JSONEncodingFailed`` when `value` can't be encoded; the report is unchanged.
    public mutating func add(json value: some Encodable, named name: String) throws(JSONEncodingFailed) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { throw JSONEncodingFailed() }
        append(data, named: name, kind: .json)
    }

    /// Adds JSON that is already encoded, as it is, in a `.json` file.
    public mutating func add(jsonData: Data, named name: String) {
        append(jsonData, named: name, kind: .json)
    }

    /// Adds an HTTP Archive (HAR 1.2 JSON), as it is, in a `.har` file.
    public mutating func add(har: Data, named name: String) {
        append(har, named: name, kind: .har)
    }

    /// Adds a PNG image, as it is, in a `.png` file.
    public mutating func add(png: Data, named name: String) {
        append(png, named: name, kind: .png)
    }

    /// Adds every file of `report` to a folder named `folder` (made safe and unique like a file
    /// name) and returns the folder's name.
    @discardableResult
    mutating func add(_ report: DebugDrawerReport, inFolder folder: String) -> String {
        let taken = Set(files.compactMap(\.folder) + files.filter { $0.folder == nil }.map(\.name))
        let safe = folder.fileNameSafe
        let unique = String.unique(safe.isEmpty ? "Plugin" : safe, extension: nil, among: taken)
        files += report.files.map { File(folder: unique, name: $0.name, kind: $0.kind, data: $0.data) }
        return unique
    }

    private mutating func append(_ data: Data, named name: String, kind: Kind) {
        let taken = Set(files.filter { $0.folder == nil }.map(\.name))
        let safe = name.fileNameSafe
        let base = safe.lowercased().hasSuffix(".\(kind.fileExtension)")
            ? String(safe.dropLast(kind.fileExtension.count + 1))
            : safe
        let unique = String.unique(base.isEmpty ? "file" : base, extension: kind.fileExtension, among: taken)
        files.append(File(folder: nil, name: unique, kind: kind, data: data))
    }
}

extension String {
    /// This name with the characters file systems reserve or treat as separators (`/`, `\`, `:`)
    /// and control characters replaced by `-`, surrounding spaces trimmed, and a leading `.`
    /// (a hidden file) dropped.
    var fileNameSafe: String {
        let reserved = CharacterSet(charactersIn: "/\\:").union(.controlCharacters)
        let replaced = String(String.UnicodeScalarView(unicodeScalars.map { reserved.contains($0) ? "-" : $0 }))
        let trimmed = replaced.trimmingCharacters(in: .whitespaces)
        return String(trimmed.drop { $0 == "." })
    }

    /// `base.ext`, or `base-2.ext`, `base-3.ext` and so on, whichever `taken` doesn't hold yet.
    /// Names compare case-insensitively, as the default file systems of macOS and iOS do.
    fileprivate static func unique(_ base: String, extension fileExtension: String?, among taken: Set<String>) -> String {
        let taken = Set(taken.map { $0.lowercased() })
        func name(_ suffix: String) -> String {
            fileExtension.map { "\(base)\(suffix).\($0)" } ?? "\(base)\(suffix)"
        }
        func isFree(_ suffix: String) -> Bool {
            !taken.contains(name(suffix).lowercased())
        }
        guard !isFree("") else { return name("") }
        // Of the taken.count + 1 suffixes from 2 on, at most taken.count are taken.
        let number = (2 ... taken.count + 2).first { isFree("-\($0)") } ?? taken.count + 2
        return name("-\(number)")
    }
}
