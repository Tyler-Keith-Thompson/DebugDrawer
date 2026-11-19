#if DEBUG
    import DebugDrawer
    import ImageIO
    import SwiftUI

    /// A file's preview: its text, JSON or property list in a code block, its image's thumbnail,
    /// or a line saying why there is none. Text cut short says how much is shown.
    struct FilePreviewView: View {
        let preview: FilePreview
        /// The file's whole size, which a cut-short preview names.
        let fileSize: Int64
        @Environment(\.locale) private var locale
        @ScaledMetric(relativeTo: .body) private var imageHeight: CGFloat = 220

        var body: some View {
            DebugDrawerSection("Preview") {
                switch preview {
                case let .text(text), let .json(text), let .propertyList(text, _):
                    PreviewTextView(text: text)
                case let .image(image):
                    if let thumbnail = image.thumbnailImage {
                        let label = "\(image.typeName) image, \(image.pixelWidth) by \(image.pixelHeight) pixels"
                        Image(thumbnail, scale: 1, label: Text(label))
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: .infinity, maxHeight: imageHeight)
                            .accessibilityLabel(label)
                    }
                case .sqlite, .empty, .binary:
                    EmptyView()
                }
            } footer: {
                if let note {
                    Text(note)
                }
            }
        }

        /// Why there's no preview, or how much of the text is shown.
        private var note: String? {
            switch preview {
            case let .text(text), let .json(text), let .propertyList(text, _):
                text.isTruncated
                    ? "Showing the first \(Int64(FilePreview.readLimit).byteCountText(locale)) of \(fileSize.byteCountText(locale))."
                    : nil
            case .image: nil
            case .sqlite: "A SQLite database has no preview here."
            case .empty: "The file is empty."
            case .binary: "No preview: the file isn't text, JSON, a property list or an image."
            }
        }
    }

    extension PreviewImage {
        /// The thumbnail's pixels, decoded from its PNG; `nil` for bytes that aren't one.
        fileprivate var thumbnailImage: CGImage? {
            CGImageSourceCreateWithData(thumbnail as CFData, nil).flatMap { CGImageSourceCreateImageAtIndex($0, 0, nil) }
        }
    }

    /// Text in a code block. A long text scrolls in a box of fixed height that builds its lines
    /// as they scroll into view, so a megabyte of it doesn't hold up the drawer.
    struct PreviewTextView: View {
        let text: PreviewText
        /// Up to this many lines show at their full height; more scroll.
        static let unscrolledLineLimit = 30
        @ScaledMetric(relativeTo: .footnote) private var height: CGFloat = 320

        var body: some View {
            DebugDrawerCodeBlock {
                if text.lines.count > Self.unscrolledLineLimit {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 2) {
                            lines
                        }
                    }
                    .frame(height: height)
                } else {
                    lines
                }
            }
        }

        private var lines: some View {
            ForEach(text.lines.indices, id: \.self) { index in
                // An empty line still takes a line's height.
                Text(text.lines[index].isEmpty ? " " : text.lines[index])
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
#endif
