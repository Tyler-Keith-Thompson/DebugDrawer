#if DEBUG && (os(macOS) || os(iOS))
    import QuartzCore

    /// Slows the Core Animation of the layers it is given by a factor, and gives each back the
    /// exact speed it had when the factor returns to 1.
    ///
    /// Each layer keeps its own speed, divided by the factor, so a layer the app had already
    /// slowed or sped up keeps that ratio. The layers are held weakly.
    @MainActor
    final class AnimationSlowdown {
        private struct Original {
            weak var layer: CALayer?
            let speed: Float
        }

        private var originals: [ObjectIdentifier: Original] = [:]

        /// Runs every layer in `layers` `factor` times slower than its own speed, or, at a factor
        /// of 1, gives back every layer slowed so far its own speed and forgets them.
        ///
        /// - Parameters:
        ///   - factor: How many times slower, 1 or more.
        ///   - layers: The windows' root layers; a layer given again keeps its first speed.
        func apply(_ factor: Double, to layers: [CALayer]) {
            guard factor != 1 else { return restore() }
            originals = originals.filter { $0.value.layer != nil }
            for layer in layers {
                let id = ObjectIdentifier(layer)
                let original = originals[id]?.speed ?? layer.speed
                originals[id] = Original(layer: layer, speed: original)
                let slowed = original / Float(factor)
                if layer.speed != slowed { layer.speed = slowed }
            }
        }

        /// Gives every layer slowed so far the speed it had before.
        func restore() {
            for original in originals.values {
                original.layer?.speed = original.speed
            }
            originals.removeAll()
        }
    }
#endif
