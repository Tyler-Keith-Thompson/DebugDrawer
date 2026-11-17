#if DEBUG
    import DebugDrawer
    import QuartzCore

    /// The drawer's own layers in a window's layer tree: those between each pair of the chrome
    /// boundary's layers (`debugDrawerChromeStartLayerName`, `debugDrawerChromeEndLayerName`) in
    /// painter's order, which the recorder hides while it draws a frame.
    ///
    /// A layer is drawn before its sublayers, and sublayers in order, so the layers painted between
    /// a start and its end are the later siblings of the start's ancestors and the earlier siblings
    /// of the end's, below their nearest common ancestor. The topmost of them are listed, since
    /// hiding a layer hides what it holds; ancestors of a boundary layer are never listed, as they
    /// hold the app too. A start with no end after it marks nothing. `zPosition` is not consulted:
    /// SwiftUI orders the drawer above the app by sublayer order alone.
    enum DrawerChromeLayers {
        /// The topmost layers of `root`'s tree painted between a chrome start and its end, the
        /// boundary layers included, in painter's order.
        ///
        /// - Complexity: O(*n*) for a tree of *n* layers.
        static func layers(in root: CALayer) -> [CALayer] {
            var holdsBoundary = Set<ObjectIdentifier>()
            func markHolders(_ layer: CALayer) -> Bool {
                var holds = layer.isChromeBoundary
                for sublayer in layer.sublayers ?? [] where markHolders(sublayer) {
                    holds = true
                }
                if holds { holdsBoundary.insert(ObjectIdentifier(layer)) }
                return holds
            }
            _ = markHolders(root)

            var found: [CALayer] = []
            var pending: [CALayer] = []
            var isInside = false
            func visit(_ layer: CALayer) {
                if layer.name == debugDrawerChromeStartLayerName {
                    // A second start before an end begins the range again.
                    pending = [layer]
                    isInside = true
                } else if layer.name == debugDrawerChromeEndLayerName {
                    if isInside { found += pending + [layer] }
                    pending = []
                    isInside = false
                } else if holdsBoundary.contains(ObjectIdentifier(layer)) {
                    for sublayer in layer.sublayers ?? [] {
                        visit(sublayer)
                    }
                } else if isInside {
                    pending.append(layer)
                }
            }
            visit(root)
            return found
        }

        /// Runs `draw` with the drawer's layers in `root`'s tree hidden, then shows them again.
        ///
        /// The layers are hidden in the model tree only, with implicit animations off, and shown
        /// again before this returns, inside one transaction, so the screen never shows the change:
        /// draw with `CALayer.render(in:)`, which renders the model tree, not with a snapshot of the
        /// screen.
        @MainActor
        static func hidden<Result>(in root: CALayer, _ draw: () -> Result) -> Result {
            let hidden = layers(in: root).filter { !$0.isHidden }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for layer in hidden {
                layer.isHidden = true
            }
            defer {
                for layer in hidden {
                    layer.isHidden = false
                }
                CATransaction.commit()
            }
            return draw()
        }
    }

    extension CALayer {
        /// Whether this is one of the chrome boundary's layers.
        fileprivate var isChromeBoundary: Bool {
            name == debugDrawerChromeStartLayerName || name == debugDrawerChromeEndLayerName
        }
    }
#endif
