#if DEBUG && os(iOS)
    import DebugDrawer
    import SceneKit
    import SwiftUI
    import UIKit

    // MARK: - 3D View Debugger (iOS)

    struct ViewDebugger3DView: UIViewRepresentable {
        let rootSnapshot: ViewSnapshot

        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        func makeUIView(context: Context) -> SCNView {
            let scnView = SCNView()
            scnView.scene = SCNScene()
            scnView.backgroundColor = UIColor(white: 0.12, alpha: 1)
            scnView.allowsCameraControl = true
            scnView.autoenablesDefaultLighting = false
            scnView.antialiasingMode = .multisampling4X
            scnView.defaultCameraController.interactionMode = .orbitTurntable

            let ambientLight = SCNNode()
            ambientLight.light = SCNLight()
            ambientLight.light?.type = .ambient
            ambientLight.light?.color = UIColor(white: 0.9, alpha: 1)
            scnView.scene?.rootNode.addChildNode(ambientLight)

            buildScene(in: scnView, context: context)
            return scnView
        }

        func updateUIView(_: SCNView, context _: Context) {}

        private let scaleFactor: Float = 0.1
        private let zSpacing: Float = 5
        private let maxRenderDepth = 8

        private func buildScene(in scnView: SCNView, context: Context) {
            guard let scene = scnView.scene else { return }

            let contentNode = SCNNode()
            scene.rootNode.addChildNode(contentNode)
            context.coordinator.contentRoot = contentNode

            let rootW = Float(rootSnapshot.frame.width) * scaleFactor
            let rootH = Float(rootSnapshot.frame.height) * scaleFactor
            addNodes(for: rootSnapshot, to: contentNode, depth: 0,
                     rootSize: CGSize(width: CGFloat(rootW), height: CGFloat(rootH)))

            let (minB, maxB) = contentNode.boundingBox
            let cx = (minB.x + maxB.x) / 2
            let cy = (minB.y + maxB.y) / 2
            let cz = (minB.z + maxB.z) / 2
            contentNode.position = SCNVector3(-cx, -cy, -cz)

            let camera = SCNCamera()
            camera.zFar = 5000
            camera.zNear = 1
            camera.fieldOfView = 40
            let cameraNode = SCNNode()
            cameraNode.camera = camera

            let extentXY = max(maxB.x - minB.x, maxB.y - minB.y)
            let distance = extentXY * 1.2
            cameraNode.position = SCNVector3(-distance * 0.3, distance * 0.3, distance)
            cameraNode.look(at: SCNVector3(0, 0, 0))

            scene.rootNode.addChildNode(cameraNode)
            scnView.pointOfView = cameraNode
            scnView.defaultCameraController.minimumVerticalAngle = -89
            scnView.defaultCameraController.maximumVerticalAngle = 89
            context.coordinator.cameraNode = cameraNode
        }

        /// Diff two images pixel-by-pixel using Core Graphics (works on any platform).
        nonisolated static func diffImage(_ image: UIImage, against background: UIImage?) -> UIImage? {
            guard let cgImage = image.cgImage else { return image }

            let width = cgImage.width
            let height = cgImage.height
            guard width > 0, height > 0 else { return image }

            guard let context = PixelDiff.rgbaContext(width: width, height: height) else { return image }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            guard let pixels = PixelDiff.pixels(of: context) else { return image }

            // backgroundPixels points into backgroundContext, kept alive until the diff is done.
            let backgroundContext = background?.cgImage.flatMap { backgroundImage -> CGContext? in
                let context = PixelDiff.rgbaContext(width: backgroundImage.width, height: backgroundImage.height)
                context?.draw(backgroundImage, in: CGRect(x: 0, y: 0, width: backgroundImage.width, height: backgroundImage.height))
                return context
            }
            let backgroundPixels = backgroundContext.flatMap(PixelDiff.pixels(of:))

            let unique = withExtendedLifetime(backgroundContext) {
                PixelDiff.clearMatching(pixels, against: backgroundPixels)
            }
            guard !PixelDiff.isNegligible(unique: unique, width: width, height: height) else { return nil }

            guard let result = context.makeImage() else { return image }
            return UIImage(cgImage: result, scale: image.scale, orientation: image.imageOrientation)
        }

        private func addNodes(for snapshot: ViewSnapshot, to parent: SCNNode, depth: Int, rootSize: CGSize) {
            guard depth <= maxRenderDepth else { return }

            let width = Float(snapshot.frame.width) * scaleFactor
            let height = Float(snapshot.frame.height) * scaleFactor
            guard width > 1, height > 1 else { return }

            if let image = snapshot.snapshotImage,
               image.size.width >= 2, image.size.height >= 2,
               image.size.width <= 4096, image.size.height <= 4096 {
                let positionX = Float(snapshot.frame.origin.x) * scaleFactor
                let positionY = Float(rootSize.height) - Float(snapshot.frame.origin.y) * scaleFactor - height
                let positionZ = Float(depth) * zSpacing

                let node = SCNNode()
                node.position = SCNVector3(positionX + width / 2, positionY + height / 2, positionZ)
                node.name = snapshot.className

                // DebugSwift approach: SCNShape + UIGraphicsImageRenderer normalization
                // to ensure Metal-compatible pixel format
                let shapeSize = CGSize(width: CGFloat(width), height: CGFloat(height))
                let path = UIBezierPath(rect: CGRect(origin: .zero, size: shapeSize))
                let shape = SCNShape(path: path, extrusionDepth: 0)
                let material = SCNMaterial()
                material.isDoubleSided = true
                material.lightingModel = .constant

                let format = UIGraphicsImageRendererFormat()
                format.scale = 1.0
                let normRenderer = UIGraphicsImageRenderer(size: image.size, format: format)
                let normalizedImage = normRenderer.image { _ in
                    image.draw(in: CGRect(origin: .zero, size: image.size))
                }
                material.diffuse.contents = normalizedImage

                shape.materials = [material]
                node.addChildNode(SCNNode(geometry: shape))
                parent.addChildNode(node)
            }

            for child in snapshot.children where !child.isHidden && child.alpha > 0.01 {
                let absoluteFrame = CGRect(
                    x: snapshot.frame.origin.x + child.frame.origin.x,
                    y: snapshot.frame.origin.y + child.frame.origin.y,
                    width: child.frame.width,
                    height: child.frame.height
                )
                let childSnapshot = ViewSnapshot(
                    className: child.className,
                    frame: absoluteFrame,
                    snapshotImage: child.snapshotImage,
                    isHidden: child.isHidden,
                    alpha: child.alpha,
                    accessibilityLabel: child.accessibilityLabel,
                    isImportant: child.isImportant,
                    children: child.children
                )
                addNodes(for: childSnapshot, to: parent, depth: depth + 1, rootSize: rootSize)
            }
        }

        private func addLabel(_ text: String, to node: SCNNode, width: Float, height: Float) {
            let textGeo = SCNText(string: text, extrusionDepth: 0)
            textGeo.font = UIFont.systemFont(ofSize: 2)
            textGeo.flatness = 0.1
            let mat = SCNMaterial()
            mat.diffuse.contents = UIColor.white.withAlphaComponent(0.7)
            mat.lightingModel = .constant
            textGeo.materials = [mat]
            let labelNode = SCNNode(geometry: textGeo)
            labelNode.position = SCNVector3(-width / 2, height / 2 + 0.5, 0.1)
            node.addChildNode(labelNode)
        }

        final class Coordinator {
            var cameraNode: SCNNode?
            var contentRoot: SCNNode?
        }
    }

    // MARK: - View snapshot model (iOS)

    struct ViewSnapshot {
        let className: String
        let frame: CGRect
        let snapshotImage: UIImage?
        let isHidden: Bool
        let alpha: CGFloat
        let accessibilityLabel: String?
        let isImportant: Bool
        let children: [ViewSnapshot]

        @MainActor
        static func capture(from view: UIView, maxDepth: Int = 10) -> ViewSnapshot {
            captureRecursive(from: view, maxDepth: maxDepth)
        }

        /// Pre-process the entire tree: diff each node's image against its parent
        /// and replace snapshotImage with the diffed version. Runs on any thread.
        static func preProcessDiffs(_ snapshot: ViewSnapshot, parentImage: UIImage?) -> ViewSnapshot {
            let diffedImage: UIImage?
            if let image = snapshot.snapshotImage {
                diffedImage = ViewDebugger3DView.diffImage(image, against: parentImage)
            } else {
                diffedImage = nil
            }

            let processedChildren = snapshot.children.map { child in
                preProcessDiffs(child, parentImage: snapshot.snapshotImage)
            }

            return ViewSnapshot(
                className: snapshot.className,
                frame: snapshot.frame,
                snapshotImage: diffedImage,
                isHidden: snapshot.isHidden,
                alpha: snapshot.alpha,
                accessibilityLabel: snapshot.accessibilityLabel,
                isImportant: snapshot.isImportant,
                children: processedChildren
            )
        }

        @MainActor
        private static func captureRecursive(from view: UIView, maxDepth: Int) -> ViewSnapshot {
            let image = captureImage(of: view)
            let className = String(describing: type(of: view))
            let important = view.accessibilityLabel != nil
                || className.contains("Hosting")

            let children: [ViewSnapshot]
            if maxDepth > 0, !view.isHidden {
                children = view.subviews.map { captureRecursive(from: $0, maxDepth: maxDepth - 1) }
            } else {
                children = []
            }

            return ViewSnapshot(
                className: className,
                frame: view.frame,
                snapshotImage: image,
                isHidden: view.isHidden,
                alpha: view.alpha,
                accessibilityLabel: view.accessibilityLabel,
                isImportant: important,
                children: children
            )
        }

        @MainActor
        private static func captureImage(of view: UIView) -> UIImage? {
            let bounds = view.bounds
            // Minimum 2pt to avoid zero/sub-pixel textures that crash Metal
            guard bounds.width >= 2, bounds.height >= 2 else { return nil }
            guard bounds.width <= 4096, bounds.height <= 4096 else { return nil }

            let renderer = UIGraphicsImageRenderer(bounds: bounds)
            let image = renderer.image { _ in
                view.drawHierarchy(in: bounds, afterScreenUpdates: false)
            }
            // Verify the resulting image has valid backing data
            guard image.cgImage != nil else { return nil }
            return image
        }
    }

    // MARK: - Request model

    struct ViewDebugger3DRequest: Identifiable {
        let id = UUID()
        let targetView: UIView
    }

    // MARK: - Combined sheet

    struct ViewDebugger3DCombinedSheet: View {
        let targetView: UIView
        @Environment(\.dismiss) private var dismiss
        @State private var snapshot: ViewSnapshot?
        @State private var status = "Capturing views..."

        var body: some View {
            VStack(spacing: 0) {
                HStack {
                    Text("3D View Hierarchy")
                        .debugDrawerFont(.title)
                        .accessibilityAddTraits(.isHeader)
                    Spacer()
                    if snapshot != nil {
                        Text("Pinch to zoom, drag to rotate")
                            .debugDrawerFont(.secondary)
                            .debugDrawerForegroundStyle(.secondary)
                    }
                    Button(snapshot == nil ? "Cancel" : "Done") { dismiss() }
                }
                .padding()

                if let snapshot {
                    ViewDebugger3DView(rootSnapshot: snapshot)
                } else {
                    Spacer()
                    ProgressView(status)
                    Spacer()
                }
            }
            .onAppear {
                DispatchQueue.main.async {
                    let captured = ViewSnapshot.capture(from: targetView)
                    // Skip diff processing on iOS — the CGContext pixel format
                    // from diffImage produces textures Metal can't validate.
                    // Use raw snapshots directly.
                    snapshot = captured
                }
            }
        }
    }
#endif
