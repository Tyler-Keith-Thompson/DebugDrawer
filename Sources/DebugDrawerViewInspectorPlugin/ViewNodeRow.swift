#if DEBUG
    import DebugDrawer
    import SwiftUI

    #if os(macOS)
    import AppKit
    #elseif os(iOS)
    import UIKit
    #endif

    /// A view in the hierarchy snapshot: its class, size and flags (hidden, alpha, clipping,
    /// corner radius, background, accessibility role and label, constraints, subviews), with its
    /// subviews in a disclosure group. Rows whose subtree doesn't match `filter` are left out.
    struct ViewNodeRow: View {
        let node: ViewNode
        let depth: Int
        /// Matched against class names, accessibility labels and roles; empty matches everything.
        let filter: String

        var body: some View {
            if subtreeMatchesFilter(node) {
                DisclosureGroup {
                    ForEach(node.children) { child in
                        ViewNodeRow(node: child, depth: depth + 1, filter: filter)
                    }
                } label: {
                    label
                }
                .padding(.leading, CGFloat(depth) * 4)
            }
        }

        // The class on one line and the flags in words joined by dots on the next, so at any
        // text size the flags wrap between words rather than each squeezing into a column.
        private var label: some View {
            VStack(alignment: .leading, spacing: 1) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if node.isHidden {
                        DebugDrawerIssueGlyph(.warning)
                            .accessibilityHidden(true)
                    }
                    if let background = node.backgroundColor {
                        swatch(background)
                    }
                    Text(node.className)
                        .debugDrawerFont(.code)
                        .debugDrawerForegroundStyle(.primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(flags.joined(separator: " · "))
                    .debugDrawerFont(.code)
                    .debugDrawerForegroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                if let label = node.accessibilityLabel {
                    Text(label)
                        .debugDrawerFont(.secondary)
                        .debugDrawerForegroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
            .padding(.vertical, 1)
        }

        /// The size and, in words, every flag that applies: hidden, alpha, clipping, corner
        /// radius, background, role, constraints and subviews.
        private var flags: [String] {
            var flags = ["\(Int(node.frame.width))×\(Int(node.frame.height))"]
            if node.isHidden { flags.append("hidden") }
            if node.alpha < 1.0 { flags.append("alpha \(String(format: "%.1f", node.alpha))") }
            if node.hasClipping { flags.append("clips") }
            if node.cornerRadius > 0 { flags.append("r\(Int(node.cornerRadius))") }
            if let background = node.backgroundColor { flags.append(background) }
            if let role = node.accessibilityRole { flags.append(role) }
            if node.constraintCount > 0 { flags.append("c\(node.constraintCount)") }
            if node.subviewCount > 0 { flags.append("(\(node.subviewCount))") }
            return flags
        }

        // The swatch shows the view's own background color: a value read from the app, not a
        // meaning, so it takes that color rather than one from the drawer's palette.
        @ViewBuilder
        private func swatch(_ hex: String) -> some View {
            #if os(macOS)
                Circle()
                    .fill(Color(nsColor: NSColor(hex: hex)))
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            #elseif os(iOS)
                Circle()
                    .fill(Color(uiColor: UIColor(hex: hex)))
                    .frame(width: 6, height: 6)
                    .accessibilityHidden(true)
            #endif
        }

        private func matchesFilter(_ node: ViewNode) -> Bool {
            guard !filter.isEmpty else { return true }
            let query = filter.lowercased()
            return node.className.lowercased().contains(query)
                || (node.accessibilityLabel?.lowercased().contains(query) ?? false)
                || (node.accessibilityRole?.lowercased().contains(query) ?? false)
        }

        private func subtreeMatchesFilter(_ node: ViewNode) -> Bool {
            if matchesFilter(node) { return true }
            return node.children.contains(where: { subtreeMatchesFilter($0) })
        }
    }

    // MARK: - Hex color init (for bg color display)

    #if os(macOS)
    private extension NSColor {
        convenience init(hex: String) {
            var digits = hex
            if digits.hasPrefix("#") { digits = String(digits.dropFirst()) }
            guard digits.count == 6, let val = UInt64(digits, radix: 16) else {
                self.init(white: 0, alpha: 1)
                return
            }
            let red = CGFloat((val >> 16) & 0xFF) / 255.0
            let green = CGFloat((val >> 8) & 0xFF) / 255.0
            let blue = CGFloat(val & 0xFF) / 255.0
            self.init(red: red, green: green, blue: blue, alpha: 1)
        }
    }
    #elseif os(iOS)
    private extension UIColor {
        convenience init(hex: String) {
            var digits = hex
            if digits.hasPrefix("#") { digits = String(digits.dropFirst()) }
            guard digits.count == 6, let val = UInt64(digits, radix: 16) else {
                self.init(white: 0, alpha: 1)
                return
            }
            let red = CGFloat((val >> 16) & 0xFF) / 255.0
            let green = CGFloat((val >> 8) & 0xFF) / 255.0
            let blue = CGFloat(val & 0xFF) / 255.0
            self.init(red: red, green: green, blue: blue, alpha: 1)
        }
    }
    #endif
#endif
