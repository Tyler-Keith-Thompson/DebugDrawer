#if DEBUG
    import CoreTransferable
    import DebugDrawer
    import Foundation
    import UniformTypeIdentifiers

    /// Requests and WebSocket connections as a HAR file to share or save: HAR 1.2, the oldest
    /// first, with what the redaction rules call sensitive masked.
    struct NetworkArchiveFile: Transferable, Sendable {
        let entries: [NetworkEntry]
        let redaction: DebugDrawerRedaction
        var webSockets: [NetworkWebSocketConnection] = []

        /// Whether it holds neither requests nor connections.
        var isEmpty: Bool {
            entries.isEmpty && webSockets.isEmpty
        }

        /// `Network <the newest request's or connection's time>.har`, the colons a file name can't
        /// hold as dashes.
        var fileName: String {
            let newest = (entries.map(\.timestamp) + webSockets.map(\.opened)).max()
            let time = newest.map { " " + $0.formatted(.iso8601).replacing(":", with: "-") } ?? ""
            return "Network\(time).har"
        }

        /// What the file holds: the archive, pretty-printed with sorted keys.
        var data: Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            // The archive is strings, numbers, Booleans and arrays of them, so encoding it can't fail.
            return (try? encoder.encode(HTTPArchive(entries, webSockets: webSockets, redaction: redaction))) ?? Data()
        }

        static var transferRepresentation: some TransferRepresentation {
            // A file rather than data, so the name keeps its `.har`: the type is one the system
            // derives from the extension, which a share sheet might not map back to it. Written
            // when the share sheet asks for it, so nothing is encoded until then.
            FileRepresentation(exportedContentType: .httpArchive) { file in
                let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let url = folder.appending(path: file.fileName, directoryHint: .notDirectory)
                try file.data.write(to: url)
                return SentTransferredFile(url)
            }
        }
    }

    extension UTType {
        /// An HTTP Archive: JSON in a `.har` file. A library can't declare a type in the app's
        /// Info.plist, so it is the type the system derives from the extension, or JSON where it
        /// derives none.
        static let httpArchive = UTType(filenameExtension: "har", conformingTo: .json) ?? .json

        /// What the importer offers: HAR files, whichever type the system gave the extension, and
        /// JSON, the name some tools give the same content.
        static let importableArchives = [httpArchive, UTType(filenameExtension: "har"), .json]
            .compactMap(\.self)
            .reduce(into: [UTType]()) { types, type in
                if !types.contains(type) { types.append(type) }
            }
    }
#endif
