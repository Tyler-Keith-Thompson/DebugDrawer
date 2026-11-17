// ImageRenderer runs SwiftUI's shaders on the Mac, so the pixels it draws are what the GPU made of
// each color.
#if os(macOS)
    import AppKit
    @testable import DebugDrawerColorVisionPlugin
    import Foundation
    import simd
    import SwiftUI
    import Testing

    @MainActor
    @Suite(.timeLimit(.minutes(1)))
    struct ColorVisionShaderTests {
        @Test("The precompiled library is raw DEFLATE in base64 that inflates to a Metal library")
        func libraryDecodes() throws {
            let compressed = try #require(Data(base64Encoded: ColorVisionShader.compressedLibrary, options: .ignoreUnknownCharacters))
            let expectedMagic = Data("MTLB".utf8)

            let actual = try (compressed as NSData).decompressed(using: .zlib) as Data

            #expect(actual.prefix(4) == expectedMagic)
        }

        @Test(
            "Each simulation draws sRGB colors as the naive reference computes them: decoded to linear, multiplied, clamped, encoded",
            arguments: ColorVision.Simulation.allCases
        )
        func pixelsMatchTheReference(simulation: ColorVision.Simulation) throws {
            // sRGB's transfer functions (IEC 61966-2-1), written out as plainly as possible.
            func linear(_ encoded: Double) -> Double {
                encoded <= 0.04045 ? encoded / 12.92 : pow((encoded + 0.055) / 1.055, 2.4)
            }
            func encoded(_ linear: Double) -> Double {
                linear <= 0.003_130_8 ? linear * 12.92 : 1.055 * pow(linear, 1 / 2.4) - 0.055
            }
            let colors: [SIMD3<Double>] = [
                SIMD3(1, 0, 0), SIMD3(0, 1, 0), SIMD3(0, 0, 1), SIMD3(1, 0.5, 0), SIMD3(0.5, 0.2, 0.8),
                SIMD3(0.2, 0.6, 0.3), SIMD3(0.5, 0.5, 0.5), SIMD3(1, 1, 1), SIMD3(0, 0, 0)
            ]
            let tolerance = 2

            for color in colors {
                let input = SIMD3(linear(color.x), linear(color.y), linear(color.z))
                let output = simd_clamp(simulation.matrix * input, SIMD3(repeating: 0), SIMD3(repeating: 1))
                let expected = [output.x, output.y, output.z].map { Int((encoded($0) * 255).rounded()) }
                let swatch = Color(.sRGB, red: color.x, green: color.y, blue: color.z)
                    .frame(width: 4, height: 4)
                    .colorVisionSimulation(simulation)
                let renderer = ImageRenderer(content: swatch)
                renderer.scale = 1
                let image = try #require(renderer.cgImage)
                let bitmap = NSBitmapImageRep(cgImage: image)
                var pixel = [Int](repeating: 0, count: 4)
                bitmap.getPixel(&pixel, atX: 2, y: 2)

                let actual = Array(pixel.prefix(3))

                #expect(zip(actual, expected).allSatisfy { abs($0 - $1) <= tolerance }, "\(simulation) of \(color): \(actual), expected \(expected)")
            }
        }

        @Test("With no simulation, content draws bit for bit as it does without the modifier")
        func offIsIdentical() throws {
            let content = ColorVisionSwatchFixture()
            let plain = ImageRenderer(content: content)
            plain.scale = 2
            let modified = ImageRenderer(content: content.colorVisionSimulation(nil))
            modified.scale = 2
            let installed = ImageRenderer(content: content.debugColorVision())
            installed.scale = 2
            let expected = try #require(plain.cgImage?.dataProvider?.data as Data?)

            let actual = try #require(modified.cgImage?.dataProvider?.data as Data?)
            let actualInstalled = try #require(installed.cgImage?.dataProvider?.data as Data?)

            #expect(actual == expected)
            #expect(actualInstalled == expected)
        }

        @Test("Turning a simulation on and then off in the same view graph draws the content bit for bit as before")
        func offRestores() throws {
            let content = ColorVisionSwatchFixture()
            let renderer = ImageRenderer(content: content.colorVisionSimulation(nil))
            renderer.scale = 2
            let expected = try #require(renderer.cgImage?.dataProvider?.data as Data?)

            renderer.content = content.colorVisionSimulation(.protanopia)
            let simulated = try #require(renderer.cgImage?.dataProvider?.data as Data?)
            renderer.content = content.colorVisionSimulation(nil)
            let actual = try #require(renderer.cgImage?.dataProvider?.data as Data?)

            #expect(simulated != expected)
            #expect(actual == expected)
        }
    }
#endif
