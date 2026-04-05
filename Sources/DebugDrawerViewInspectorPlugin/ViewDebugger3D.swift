#if DEBUG
    import SceneKit
    import SwiftUI

    #if os(macOS)
    import AppKit

    // MARK: - 3D View Debugger

    struct ViewDebugger3DView: NSViewRepresentable {
        let rootSnapshot: ViewSnapshot

        func makeCoordinator() -> Coordinator {
            Coordinator()
        }

        func makeNSView(context: Context) -> SCNView {
            let scnView = SCNView()
            scnView.scene = SCNScene()
            scnView.backgroundColor = NSColor(white: 0.12, alpha: 1)
            scnView.allowsCameraControl = true
            scnView.autoenablesDefaultLighting = false
            scnView.antialiasingMode = .multisampling4X
            scnView.defaultCameraController.interactionMode = .orbitTurntable

            let ambientLight = SCNNode()
            ambientLight.light = SCNLight()
            ambientLight.light?.type = .ambient
            ambientLight.light?.color = NSColor(white: 0.9, alpha: 1)
            scnView.scene?.rootNode.addChildNode(ambientLight)

            buildScene(in: scnView, context: context)
            return scnView
        }

        func updateNSView(_: SCNView, context _: Context) {}

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

        /// Diff two images pixel-by-pixel: make any pixel in `image` that matches
        /// the corresponding pixel in `background` transparent. Returns the diffed image,
        /// or nil if the entire image matched (nothing unique).
        /// This is intentionally nonisolated so it can run on a background thread.
        nonisolated static func diffImage(_ image: NSImage, against background: NSImage?) -> NSImage? {
            guard let tiff = image.tiffRepresentation,
                  let rep = NSBitmapImageRep(data: tiff),
                  let pixels = rep.bitmapData
            else { return image }

            let w = rep.pixelsWide
            let h = rep.pixelsHigh
            let bpp = rep.bitsPerPixel / 8
            let rowBytes = rep.bytesPerRow
            guard w > 0, h > 0, bpp >= 3 else { return image }

            // Get background pixel data if available
            var bgPixels: UnsafeMutablePointer<UInt8>?
            var bgRep: NSBitmapImageRep?
            var bgW = 0, bgH = 0, bgBpp = 0, bgRowBytes = 0

            if let bg = background,
               let bgTiff = bg.tiffRepresentation,
               let r = NSBitmapImageRep(data: bgTiff),
               let p = r.bitmapData
            {
                bgRep = r // keep alive
                bgPixels = p
                bgW = r.pixelsWide
                bgH = r.pixelsHigh
                bgBpp = r.bitsPerPixel / 8
                bgRowBytes = r.bytesPerRow
            }

            // Create a mutable copy with alpha
            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(
                      data: nil, width: w, height: h,
                      bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { return image }

            // Draw the original image into our RGBA context
            if let cgImage = rep.cgImage {
                ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            }

            guard let outPixels = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return image }
            let outRowBytes = w * 4

            var uniquePixels = 0
            let tolerance = 32 // per-channel tolerance — high to catch sub-pixel text anti-aliasing

            for y in 0 ..< h {
                for x in 0 ..< w {
                    let outOff = y * outRowBytes + x * 4

                    if let bgP = bgPixels, x < bgW, y < bgH, bgBpp >= 3 {
                        // Map coordinates: child might be smaller/offset from parent
                        let bgOff = y * bgRowBytes + x * bgBpp
                        let dr = abs(Int(outPixels[outOff]) - Int(bgP[bgOff]))
                        let dg = abs(Int(outPixels[outOff + 1]) - Int(bgP[bgOff + 1]))
                        let db = abs(Int(outPixels[outOff + 2]) - Int(bgP[bgOff + 2]))

                        if dr <= tolerance, dg <= tolerance, db <= tolerance {
                            // Same pixel — make transparent
                            outPixels[outOff] = 0
                            outPixels[outOff + 1] = 0
                            outPixels[outOff + 2] = 0
                            outPixels[outOff + 3] = 0
                            continue
                        }
                    }
                    uniquePixels += 1
                }
            }

            // If less than 0.5% of pixels are unique, skip this layer entirely
            let totalPixels = w * h
            guard uniquePixels > totalPixels / 200 else { return nil }

            guard let cgResult = ctx.makeImage() else { return image }
            _ = bgRep // prevent premature release
            return NSImage(cgImage: cgResult, size: image.size)
        }

        /// Images are already pre-processed (diffed) — just build the SceneKit nodes.
        private func addNodes(for snapshot: ViewSnapshot, to parent: SCNNode, depth: Int, rootSize: CGSize) {
            guard depth <= maxRenderDepth else { return }

            let w = Float(snapshot.frame.width) * scaleFactor
            let h = Float(snapshot.frame.height) * scaleFactor
            guard w > 1, h > 1 else { return }

            if let image = snapshot.snapshotImage,
               image.size.width >= 2, image.size.height >= 2,
               image.size.width <= 4096, image.size.height <= 4096
            {
                let x = Float(snapshot.frame.origin.x) * scaleFactor
                let y = Float(rootSize.height) - Float(snapshot.frame.origin.y) * scaleFactor - h
                let z = Float(depth) * zSpacing

                let node = SCNNode()
                node.position = SCNVector3(x + w / 2, y + h / 2, z)
                node.name = snapshot.className

                let plane = SCNPlane(width: CGFloat(w), height: CGFloat(h))
                let material = SCNMaterial()
                material.isDoubleSided = true
                material.lightingModel = .constant
                material.diffuse.contents = image
                material.blendMode = .alpha
                plane.materials = [material]
                node.addChildNode(SCNNode(geometry: plane))
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
            textGeo.font = NSFont.systemFont(ofSize: 2)
            textGeo.flatness = 0.1
            let mat = SCNMaterial()
            mat.diffuse.contents = NSColor.white.withAlphaComponent(0.7)
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

    // MARK: - View snapshot model

    struct ViewSnapshot {
        let className: String
        let frame: CGRect
        let snapshotImage: NSImage?
        let isHidden: Bool
        let alpha: CGFloat
        let accessibilityLabel: String?
        let isImportant: Bool
        let children: [ViewSnapshot]

        @MainActor
        static func capture(from view: NSView, maxDepth: Int = 10) -> ViewSnapshot {
            captureRecursive(from: view, maxDepth: maxDepth)
        }

        /// Pre-process the entire tree: diff each node's image against its parent
        /// and replace snapshotImage with the diffed version. Runs on any thread.
        static func preProcessDiffs(_ snapshot: ViewSnapshot, parentImage: NSImage?) -> ViewSnapshot {
            let diffedImage: NSImage?
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
        private static func captureRecursive(from view: NSView, maxDepth: Int) -> ViewSnapshot {
            let image = captureImage(of: view)
            let className = String(describing: type(of: view))
            let important = view.accessibilityLabel() != nil
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
                alpha: CGFloat(view.alphaValue),
                accessibilityLabel: view.accessibilityLabel(),
                isImportant: important,
                children: children
            )
        }

        @MainActor
        private static func captureImage(of view: NSView) -> NSImage? {
            let bounds = view.bounds
            guard bounds.width > 0, bounds.height > 0 else { return nil }
            guard bounds.width <= 4096, bounds.height <= 4096 else { return nil }

            // NSVisualEffectView renders as opaque white when snapshotted directly.
            // Snapshot the window and crop to this view's rect instead.
            if view is NSVisualEffectView, let window = view.window {
                let rectInWindow = view.convert(bounds, to: nil)
                let windowBounds = window.contentView?.bounds ?? .zero
                // Flip Y for window coordinates
                let flippedRect = CGRect(
                    x: rectInWindow.origin.x,
                    y: windowBounds.height - rectInWindow.origin.y - rectInWindow.height,
                    width: rectInWindow.width,
                    height: rectInWindow.height
                )
                if let windowImage = window.contentView?.bitmapImageRepForCachingDisplay(in: windowBounds) {
                    window.contentView?.cacheDisplay(in: windowBounds, to: windowImage)
                    if let fullCG = windowImage.cgImage, let cropped = fullCG.cropping(to: flippedRect) {
                        return NSImage(cgImage: cropped, size: bounds.size)
                    }
                }
            }

            guard let bitmapRep = view.bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
            view.cacheDisplay(in: bounds, to: bitmapRep)
            let image = NSImage(size: bounds.size)
            image.addRepresentation(bitmapRep)
            return image
        }
    }

    // MARK: - Request model

    struct ViewDebugger3DRequest: Identifiable {
        let id = UUID()
        let targetView: NSView
    }

    // MARK: - Combined sheet

    struct ViewDebugger3DCombinedSheet: View {
        let targetView: NSView
        @Environment(\.dismiss) private var dismiss
        @State private var snapshot: ViewSnapshot?
        @State private var status = "Capturing views..."

        var body: some View {
            VStack(spacing: 0) {
                HStack {
                    Text("3D View Hierarchy")
                        .font(.headline)
                    Spacer()
                    if snapshot != nil {
                        Text("Option+scroll to zoom, drag to rotate")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Button(snapshot == nil ? "Cancel" : "Done") { dismiss() }
                        .keyboardShortcut(.escape)
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
            .frame(minWidth: 800, minHeight: 600)
            .onAppear {
                // Phase 1: Capture on main thread (AppKit requirement)
                DispatchQueue.main.async {
                    let captured = ViewSnapshot.capture(from: targetView)
                    status = "Processing layers..."

                    // Phase 2: Pre-process pixel diffs on background queue
                    DispatchQueue.global(qos: .userInitiated).async {
                        let processed = ViewSnapshot.preProcessDiffs(captured, parentImage: nil)
                        DispatchQueue.main.async {
                            snapshot = processed
                        }
                    }
                }
            }
        }
    }

    #elseif os(iOS)

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

            let w = cgImage.width
            let h = cgImage.height
            guard w > 0, h > 0 else { return image }

            guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
                  let ctx = CGContext(
                      data: nil, width: w, height: h,
                      bitsPerComponent: 8, bytesPerRow: w * 4,
                      space: colorSpace,
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else { return image }

            ctx.draw(cgImage, in: CGRect(x: 0, y: 0, width: w, height: h))
            guard let outPixels = ctx.data?.assumingMemoryBound(to: UInt8.self) else { return image }
            let outRowBytes = w * 4

            // Background pixels
            var bgCtx: CGContext?
            var bgPixels: UnsafeMutablePointer<UInt8>?
            var bgW = 0, bgH = 0

            if let bgCG = background?.cgImage {
                bgW = bgCG.width
                bgH = bgCG.height
                bgCtx = CGContext(
                    data: nil, width: bgW, height: bgH,
                    bitsPerComponent: 8, bytesPerRow: bgW * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                )
                bgCtx?.draw(bgCG, in: CGRect(x: 0, y: 0, width: bgW, height: bgH))
                bgPixels = bgCtx?.data?.assumingMemoryBound(to: UInt8.self)
            }

            var uniquePixels = 0
            let tolerance = 32

            for y in 0 ..< h {
                for x in 0 ..< w {
                    let outOff = y * outRowBytes + x * 4

                    if let bgP = bgPixels, x < bgW, y < bgH {
                        let bgOff = y * (bgW * 4) + x * 4
                        let dr = abs(Int(outPixels[outOff]) - Int(bgP[bgOff]))
                        let dg = abs(Int(outPixels[outOff + 1]) - Int(bgP[bgOff + 1]))
                        let db = abs(Int(outPixels[outOff + 2]) - Int(bgP[bgOff + 2]))

                        if dr <= tolerance, dg <= tolerance, db <= tolerance {
                            outPixels[outOff] = 0
                            outPixels[outOff + 1] = 0
                            outPixels[outOff + 2] = 0
                            outPixels[outOff + 3] = 0
                            continue
                        }
                    }
                    uniquePixels += 1
                }
            }

            let totalPixels = w * h
            guard uniquePixels > totalPixels / 200 else { return nil }

            guard let cgResult = ctx.makeImage() else { return image }
            return UIImage(cgImage: cgResult, scale: image.scale, orientation: image.imageOrientation)
        }

        private func addNodes(for snapshot: ViewSnapshot, to parent: SCNNode, depth: Int, rootSize: CGSize) {
            guard depth <= maxRenderDepth else { return }

            let w = Float(snapshot.frame.width) * scaleFactor
            let h = Float(snapshot.frame.height) * scaleFactor
            guard w > 1, h > 1 else { return }

            if let image = snapshot.snapshotImage,
               image.size.width >= 2, image.size.height >= 2,
               image.size.width <= 4096, image.size.height <= 4096
            {
                let x = Float(snapshot.frame.origin.x) * scaleFactor
                let y = Float(rootSize.height) - Float(snapshot.frame.origin.y) * scaleFactor - h
                let z = Float(depth) * zSpacing

                let node = SCNNode()
                node.position = SCNVector3(x + w / 2, y + h / 2, z)
                node.name = snapshot.className

                // DebugSwift approach: SCNShape + UIGraphicsImageRenderer normalization
                // to ensure Metal-compatible pixel format
                let shapeSize = CGSize(width: CGFloat(w), height: CGFloat(h))
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
                        .font(.headline)
                    Spacer()
                    if snapshot != nil {
                        Text("Pinch to zoom, drag to rotate")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

    #endif // os(iOS)
#endif
