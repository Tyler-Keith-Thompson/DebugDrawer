#if DEBUG
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
        @Environment(\.dynamicTypeSize) private var dynamicTypeSize

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

        // At accessibility text sizes a row of flags squeezes each one to a few letters per line,
        // so each flag takes a line of its own.
        private func flagLayout(spacing: CGFloat) -> AnyLayout {
            dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 1))
                : AnyLayout(HStackLayout(spacing: spacing))
        }

        private var label: some View {
            let classLayout = flagLayout(spacing: 4)
            let detailLayout = flagLayout(spacing: 6)
            return VStack(alignment: .leading, spacing: 1) {
                classLayout {
                    Text(node.className)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(node.accessibilityLabel != nil ? Color.accentColor : .primary)

                    if node.isHidden {
                        Text("HIDDEN")
                            .font(.system(.caption2, design: .monospaced, weight: .bold))
                            .foregroundStyle(.red)
                    }

                    if node.alpha < 1.0 {
                        Text("a\(node.alpha, specifier: "%.1f")")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.orange)
                    }

                    if node.hasClipping {
                        Text("CLIP")
                            .font(.system(.caption2, design: .monospaced, weight: .bold))
                            .foregroundStyle(.purple)
                    }
                }

                detailLayout {
                    Text("\(Int(node.frame.width))x\(Int(node.frame.height))")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.tertiary)

                    if node.cornerRadius > 0 {
                        Text("r\(Int(node.cornerRadius))")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.cyan)
                    }

                    if let bg = node.backgroundColor {
                        HStack(spacing: 2) {
                            #if os(macOS)
                            Circle()
                                .fill(Color(nsColor: NSColor(hex: bg)))
                                .frame(width: 6, height: 6)
                            #elseif os(iOS)
                            Circle()
                                .fill(Color(uiColor: UIColor(hex: bg)))
                                .frame(width: 6, height: 6)
                            #endif
                            Text(bg)
                                .font(.system(.caption2, design: .monospaced))
                                .foregroundStyle(.tertiary)
                        }
                    }

                    if let role = node.accessibilityRole {
                        Text(role)
                            .font(.system(.caption2, design: .monospaced))
                            .padding(.horizontal, 3)
                            .background(Color.purple.opacity(0.15))
                            .cornerRadius(2)
                    }

                    if let label = node.accessibilityLabel {
                        Text(label)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }

                    if node.constraintCount > 0 {
                        Text("c\(node.constraintCount)")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }

                    if node.subviewCount > 0 {
                        Text("(\(node.subviewCount))")
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.vertical, 1)
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
