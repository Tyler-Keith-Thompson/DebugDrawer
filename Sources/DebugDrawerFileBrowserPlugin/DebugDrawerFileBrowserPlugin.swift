#if DEBUG
    #if os(macOS)
        import AppKit
    #elseif os(iOS)
        import UIKit
    #endif
    import DebugDrawer
    import SwiftUI

    // MARK: - File system model

    struct FSNode: Identifiable {
        let id = UUID()
        let name: String
        let path: String
        let isDirectory: Bool
        let size: Int64
        let modified: Date?
        let children: [FSNode]?

        var sizeLabel: String {
            if isDirectory { return "" }
            if size < 1024 { return "\(size) B" }
            if size < 1024 * 1024 { return "\(size / 1024) KB" }
            return String(format: "%.1f MB", Double(size) / (1024 * 1024))
        }

        static func scan(at path: String, depth: Int = 0, maxDepth: Int = 2) -> FSNode {
            let fm = FileManager.default
            let name = (path as NSString).lastPathComponent
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDir) else {
                return FSNode(name: name, path: path, isDirectory: false, size: 0, modified: nil, children: nil)
            }

            let attrs = try? fm.attributesOfItem(atPath: path)
            let size = attrs?[.size] as? Int64 ?? 0
            let modified = attrs?[.modificationDate] as? Date

            if isDir.boolValue, depth < maxDepth {
                let contents = (try? fm.contentsOfDirectory(atPath: path)) ?? []
                let children = contents.sorted().map { child in
                    scan(at: (path as NSString).appendingPathComponent(child), depth: depth + 1, maxDepth: maxDepth)
                }
                return FSNode(name: name, path: path, isDirectory: true, size: 0, modified: modified, children: children)
            }

            return FSNode(name: name, path: path, isDirectory: isDir.boolValue, size: size, modified: modified, children: isDir.boolValue ? [] : nil)
        }
    }

    // MARK: - Scan location

    struct ScanLocation {
        let label: String
        let path: String
        let maxDepth: Int
    }

    struct ScannedRoot: Identifiable {
        let id = UUID()
        let label: String
        let node: FSNode
    }

    // MARK: - Plugin

    public struct FileBrowserPlugin: DebugDrawerPlugin {
        public var title = "File Browser"
        public var icon = "folder"

        public init() {}

        public var body: some View {
            FileBrowserPluginView()
        }
    }

    struct FileBrowserPluginView: View {
        @State private var roots: [ScannedRoot] = []
        @State private var isScanning = false
        @State private var scanProgress = ""
        @State private var fileToDelete: String?
        @State private var showDeleteAlert = false

        private static let scanQueue = DispatchQueue(label: "com.debugdrawer.filescan", qos: .utility)

        var body: some View {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("Sandboxed Directories")
                        .font(.caption.weight(.medium))
                    Spacer()
                    if isScanning {
                        ProgressView()
                            .controlSize(.small)
                        Text(scanProgress)
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)
                    }
                    Button(roots.isEmpty ? "Scan" : "Refresh") { scan() }
                        .font(.caption)
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(isScanning)
                }

                if !roots.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(roots) { root in
                                VStack(alignment: .leading, spacing: 0) {
                                    Text(root.label)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .padding(.vertical, 4)

                                    Text(root.node.path)
                                        .font(.system(size: 8, design: .monospaced))
                                        .foregroundStyle(.tertiary)
                                        .lineLimit(1)
                                        .truncationMode(.head)
                                        .textSelection(.enabled)

                                    if let children = root.node.children {
                                        ForEach(children) { child in
                                            fileRow(child, depth: 0)
                                        }
                                    }

                                    Divider().padding(.vertical, 4)
                                }
                            }
                        }
                        .padding(.horizontal, 4)
                    }
                    .frame(maxHeight: 300)
                    .background(Color.black.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .alert("Delete File", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) { fileToDelete = nil }
                Button("Delete", role: .destructive) {
                    if let path = fileToDelete {
                        deleteFile(at: path)
                    }
                    fileToDelete = nil
                }
            } message: {
                Text("Are you sure you want to delete this file? This cannot be undone.")
            }
        }

        private func deleteFile(at path: String) {
            do {
                try FileManager.default.removeItem(atPath: path)
                // Refresh to reflect the deletion
                scan()
            } catch {
                // Silently fail — the file may already be gone
            }
        }

        private func shareFile(at path: String) {
            let fileURL = URL(fileURLWithPath: path)
            #if os(macOS)
                guard let window = NSApp.keyWindow else { return }
                let picker = NSSharingServicePicker(items: [fileURL])
                // Show anchored to the window's content view center
                if let contentView = window.contentView {
                    let rect = CGRect(x: contentView.bounds.midX, y: contentView.bounds.midY, width: 1, height: 1)
                    picker.show(relativeTo: rect, of: contentView, preferredEdge: .minY)
                }
            #elseif os(iOS)
                let activityVC = UIActivityViewController(activityItems: [fileURL], applicationActivities: nil)
                guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                      let rootVC = scene.windows.first?.rootViewController
                else { return }
                // Find the topmost presented controller
                var presenter = rootVC
                while let presented = presenter.presentedViewController {
                    presenter = presented
                }
                if let popover = activityVC.popoverPresentationController {
                    popover.sourceView = presenter.view
                    popover.sourceRect = CGRect(x: presenter.view.bounds.midX, y: presenter.view.bounds.midY, width: 0, height: 0)
                }
                presenter.present(activityVC, animated: true)
            #endif
        }

        private func scan() {
            isScanning = true
            roots = []

            let locations = Self.buildLocations()

            // Scan each location one at a time on a background queue,
            // streaming results to the UI as each completes.
            Self.scanQueue.async {
                for location in locations {
                    DispatchQueue.main.async {
                        scanProgress = location.label
                    }
                    let node = FSNode.scan(at: location.path, maxDepth: location.maxDepth)
                    let root = ScannedRoot(label: location.label, node: node)
                    DispatchQueue.main.async {
                        roots.append(root)
                    }
                }
                DispatchQueue.main.async {
                    isScanning = false
                    scanProgress = ""
                }
            }
        }

        private static func buildLocations() -> [ScanLocation] {
            var result: [ScanLocation] = []
            let fm = FileManager.default
            let bundleId = Bundle.main.bundleIdentifier ?? "com.mergeward.app"

            // Only scan app-specific directories, not broad system locations.
            if let appSupport = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
                let dir = appSupport.appendingPathComponent(bundleId).path
                if fm.fileExists(atPath: dir) {
                    result.append(ScanLocation(label: "App Support", path: dir, maxDepth: 2))
                }
            }

            if let caches = fm.urls(for: .cachesDirectory, in: .userDomainMask).first {
                let dir = caches.appendingPathComponent(bundleId).path
                if fm.fileExists(atPath: dir) {
                    result.append(ScanLocation(label: "Caches", path: dir, maxDepth: 1))
                }
            }

            return result
        }

        private func fileRow(_ node: FSNode, depth: Int) -> AnyView {
            AnyView(VStack(alignment: .leading, spacing: 0) {
                if node.isDirectory, let children = node.children, !children.isEmpty {
                    DisclosureGroup {
                        ForEach(children) { child in
                            fileRow(child, depth: depth + 1)
                        }
                    } label: {
                        fileLabel(node)
                    }
                } else {
                    fileLabel(node)
                }
            }
            .padding(.leading, CGFloat(depth) * 8))
        }

        private func fileLabel(_ node: FSNode) -> some View {
            HStack(spacing: 4) {
                Image(systemName: node.isDirectory ? "folder.fill" : fileIcon(node.name))
                    .font(.system(size: 9))
                    .foregroundStyle(node.isDirectory ? .blue : .secondary)
                    .frame(width: 14)

                Text(node.name)
                    .font(.system(size: 10, design: .monospaced))
                    .lineLimit(1)

                Spacer()

                if !node.isDirectory {
                    Text(node.sizeLabel)
                        .font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.tertiary)

                    Button(role: .destructive) {
                        fileToDelete = node.path
                        showDeleteAlert = true
                    } label: {
                        Image(systemName: "trash")
                            .font(.system(size: 9))
                            .foregroundStyle(.red.opacity(0.6))
                    }
                    .buttonStyle(.plain)

                    Button {
                        shareFile(at: node.path)
                    } label: {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 2)
            .contextMenu {
                Button("Copy Path") {
                    debugDrawerCopyToClipboard(node.path)
                }
                if !node.isDirectory {
                    Button("Share...") {
                        shareFile(at: node.path)
                    }
                    Button("Delete", role: .destructive) {
                        fileToDelete = node.path
                        showDeleteAlert = true
                    }
                }
                #if os(macOS)
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.selectFile(node.path, inFileViewerRootedAtPath: "")
                    }
                #endif
            }
        }

        private func fileIcon(_ name: String) -> String {
            let ext = (name as NSString).pathExtension.lowercased()
            switch ext {
            case "json": return "doc.text"
            case "sqlite", "db": return "cylinder"
            case "plist": return "list.bullet.rectangle"
            case "log", "txt": return "doc.plaintext"
            case "png", "jpg", "jpeg", "gif", "svg": return "photo"
            default: return "doc"
            }
        }
    }

    // MARK: - Convenience installer

    public extension DebugDrawer {
        func installFileBrowser() {
            registerGlobal(FileBrowserPlugin())
        }
    }
#endif
