#if DEBUG
    import Combine
    import DebugDrawer
    import SwiftUI

    #if os(macOS)
    import AppKit
    #elseif os(iOS)
    import UIKit
    #endif

    // MARK: - View hierarchy model

    #if os(macOS)

    struct ViewNode: Identifiable {
        let id = UUID()
        let className: String
        let frame: NSRect
        let accessibilityLabel: String?
        let accessibilityRole: String?
        let isHidden: Bool
        let alpha: CGFloat
        let hasClipping: Bool
        let cornerRadius: CGFloat
        let backgroundColor: String?
        let constraintCount: Int
        let subviewCount: Int
        let children: [ViewNode]

        @MainActor static func build(from view: NSView, maxDepth: Int = 12) -> ViewNode {
            let children: [ViewNode]
            if maxDepth > 0 {
                children = view.subviews.map { build(from: $0, maxDepth: maxDepth - 1) }
            } else {
                children = []
            }

            let bgColor: String? = if let bg = view.layer?.backgroundColor {
                NSColor(cgColor: bg)?.hexString
            } else {
                nil
            }

            return ViewNode(
                className: String(describing: type(of: view)),
                frame: view.frame,
                accessibilityLabel: view.accessibilityLabel(),
                accessibilityRole: view.accessibilityRole()?.rawValue,
                isHidden: view.isHidden,
                alpha: CGFloat(view.alphaValue),
                hasClipping: view.layer?.masksToBounds ?? false,
                cornerRadius: view.layer?.cornerRadius ?? 0,
                backgroundColor: bgColor,
                constraintCount: view.constraints.count,
                subviewCount: view.subviews.count,
                children: children
            )
        }
    }

    private extension NSColor {
        var hexString: String? {
            guard let rgb = usingColorSpace(.sRGB) else { return nil }
            let red = Int(rgb.redComponent * 255)
            let green = Int(rgb.greenComponent * 255)
            let blue = Int(rgb.blueComponent * 255)
            return String(format: "#%02X%02X%02X", red, green, blue)
        }
    }

    #elseif os(iOS)

    struct ViewNode: Identifiable {
        let id = UUID()
        let className: String
        let frame: CGRect
        let accessibilityLabel: String?
        let accessibilityRole: String?
        let isHidden: Bool
        let alpha: CGFloat
        let hasClipping: Bool
        let cornerRadius: CGFloat
        let backgroundColor: String?
        let constraintCount: Int
        let subviewCount: Int
        let children: [ViewNode]

        @MainActor static func build(from view: UIView, maxDepth: Int = 12) -> ViewNode {
            let children: [ViewNode]
            if maxDepth > 0 {
                children = view.subviews.map { build(from: $0, maxDepth: maxDepth - 1) }
            } else {
                children = []
            }

            let bgColor: String? = if let bg = view.layer.backgroundColor, bg.alpha > 0.01 {
                UIColor(cgColor: bg).hexString
            } else {
                nil
            }

            return ViewNode(
                className: String(describing: type(of: view)),
                frame: view.frame,
                accessibilityLabel: view.accessibilityLabel,
                accessibilityRole: nil, // UIKit uses accessibilityTraits instead of roles
                isHidden: view.isHidden,
                alpha: view.alpha,
                hasClipping: view.layer.masksToBounds,
                cornerRadius: view.layer.cornerRadius,
                backgroundColor: bgColor,
                constraintCount: view.constraints.count,
                subviewCount: view.subviews.count,
                children: children
            )
        }
    }

    private extension UIColor {
        var hexString: String? {
            var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
            getRed(&red, green: &green, blue: &blue, alpha: &alpha)
            return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
        }
    }

    #endif
#endif
