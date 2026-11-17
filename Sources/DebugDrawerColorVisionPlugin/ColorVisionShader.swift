#if DEBUG
    import Foundation
    import simd
    import SwiftUI

    // How the matrix is applied: SwiftUI's `colorEffect` with a `[[stitchable]]` Metal function, all
    // public API (iOS 17, macOS 14, tvOS 17, visionOS 1). SwiftUI runs it on the GPU each frame the
    // content draws, so the simulation is live. Rejected:
    // - Compiling the shader at runtime (`MTLDevice.makeLibrary(source:)`): SwiftUI's ShaderLibrary
    //   takes only a compiled library's data or URL, a runtime library can't be serialized, and a
    //   serialized `MTLDynamicLibrary` traps in Metal's function validation when its function is
    //   looked up.
    // - A `.metal` resource compiled by the build: it needs Xcode's Metal toolchain, an 840 MB
    //   download, on every machine that builds the package, apps' included, and puts a resource
    //   bundle into their release builds. So the library ships precompiled (tools/metallibs.py),
    //   under `#if DEBUG`.
    // - SwiftUI's own color modifiers: `grayscale` has its own weights and `saturation` clamps
    //   between steps, so a chain with them doesn't compose into these matrices, and one of
    //   `colorMultiply` and `hueRotation` alone would rest on how SwiftUI composes them, which is
    //   undocumented. `_colorMatrix(_:)` would do it, but it is an undocumented symbol.
    // - Core Image's CIColorMatrix: it filters an image, so the app would have to be snapshotted
    //   each frame, which is slow and a frame behind; `CALayer.filters` takes Core Image filters on
    //   macOS only, and `CAFilter` is private.

    /// The Metal shader that applies a simulation's matrix to each pixel.
    enum ColorVisionShader {
        /// The shader library, decompressed from the platform's precompiled data
        /// (`compressedLibrary`).
        static let library: ShaderLibrary = {
            // The force unwrap and the trap decode a constant tools/metallibs.py wrote and
            // ColorVisionShaderTests decodes, so neither can fire at runtime, and no caller could
            // recover from a shader that is missing.
            let compressed = Data(base64Encoded: compressedLibrary, options: .ignoreUnknownCharacters)!
            do {
                return ShaderLibrary(data: try (compressed as NSData).decompressed(using: .zlib) as Data)
            } catch {
                preconditionFailure("The precompiled Color Vision shader isn't raw DEFLATE: run `just metallibs`")
            }
        }()

        /// The shader that simulates `simulation`: it decodes each pixel to linear sRGB, applies
        /// the simulation's matrix, and encodes it again.
        static func shader(simulating simulation: ColorVision.Simulation) -> Shader {
            library.colorVisionSimulation(.floatArray(simulation.matrix.rowMajor))
        }
    }

    extension simd_double3x3 {
        /// The matrix's nine entries, row by row, as the shader reads them.
        fileprivate var rowMajor: [Float] {
            let transposed = transpose
            return [transposed.columns.0, transposed.columns.1, transposed.columns.2].flatMap { [Float($0.x), Float($0.y), Float($0.z)] }
        }
    }

    extension View {
        /// The view with `simulation` applied to its colors; with `nil`, the view as it is.
        ///
        /// With `nil` the effect is left out, not disabled: SwiftUI draws the views UIKit and
        /// AppKit back as placeholders under a `colorEffect` even with `isEnabled` false. So the
        /// content takes a new identity, and its state starts over, when a simulation turns on or
        /// off; a change from one simulation to another keeps it.
        @ViewBuilder
        func colorVisionSimulation(_ simulation: ColorVision.Simulation?) -> some View {
            if let simulation {
                colorEffect(ColorVisionShader.shader(simulating: simulation))
            } else {
                self
            }
        }
    }
#endif
