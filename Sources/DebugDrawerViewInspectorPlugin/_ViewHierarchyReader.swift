#if DEBUG && (os(macOS) || os(iOS))
    import DebugDrawer

    #if os(macOS)
        import AppKit
    #else
        // Mac Catalyst too: its windows are UIWindows, as on iOS.
        import UIKit
    #endif

    /// Walks the app's key window, never the drawer's, twelve views deep.
    struct _ViewHierarchyReader: ViewHierarchyReader {
        func keyWindowHierarchy() -> ViewNode? {
            #if os(macOS)
                debugDrawerAppKeyWindow?.contentView.map { ViewNode(reading: $0) }
            #else
                debugDrawerAppKeyWindow?.rootViewController?.view.map { ViewNode(reading: $0) }
            #endif
        }
    }

    #if os(macOS)
        extension ViewNode {
            /// `view` and its subviews, `maxDepth` levels down.
            @MainActor fileprivate init(reading view: NSView, maxDepth: Int = 12) {
                self.init(
                    className: String(describing: type(of: view)),
                    frame: view.frame,
                    accessibilityLabel: view.accessibilityLabel(),
                    accessibilityRole: view.accessibilityRole()?.rawValue,
                    isHidden: view.isHidden,
                    alpha: CGFloat(view.alphaValue),
                    hasClipping: view.layer?.masksToBounds ?? false,
                    cornerRadius: view.layer?.cornerRadius ?? 0,
                    backgroundColor: view.layer?.backgroundColor.flatMap { NSColor(cgColor: $0)?.hexString },
                    constraintCount: view.constraints.count,
                    subviewCount: view.subviews.count,
                    children: maxDepth > 0 ? view.subviews.map { ViewNode(reading: $0, maxDepth: maxDepth - 1) } : []
                )
            }
        }

        extension NSColor {
            fileprivate var hexString: String? {
                guard let rgb = usingColorSpace(.sRGB) else { return nil }
                let red = Int(rgb.redComponent * 255)
                let green = Int(rgb.greenComponent * 255)
                let blue = Int(rgb.blueComponent * 255)
                return String(format: "#%02X%02X%02X", red, green, blue)
            }
        }
    #else
        extension ViewNode {
            /// `view` and its subviews, `maxDepth` levels down.
            @MainActor fileprivate init(reading view: UIView, maxDepth: Int = 12) {
                let background: String? = if let color = view.layer.backgroundColor, color.alpha > 0.01 {
                    UIColor(cgColor: color).hexString
                } else {
                    nil
                }
                self.init(
                    className: String(describing: type(of: view)),
                    frame: view.frame,
                    accessibilityLabel: view.accessibilityLabel,
                    accessibilityRole: nil, // UIKit uses accessibilityTraits instead of roles
                    isHidden: view.isHidden,
                    alpha: view.alpha,
                    hasClipping: view.layer.masksToBounds,
                    cornerRadius: view.layer.cornerRadius,
                    backgroundColor: background,
                    constraintCount: view.constraints.count,
                    subviewCount: view.subviews.count,
                    children: maxDepth > 0 ? view.subviews.map { ViewNode(reading: $0, maxDepth: maxDepth - 1) } : []
                )
            }
        }

        extension UIColor {
            fileprivate var hexString: String {
                var red: CGFloat = 0, green: CGFloat = 0, blue: CGFloat = 0, alpha: CGFloat = 0
                getRed(&red, green: &green, blue: &blue, alpha: &alpha)
                return String(format: "#%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
            }
        }
    #endif
#endif
