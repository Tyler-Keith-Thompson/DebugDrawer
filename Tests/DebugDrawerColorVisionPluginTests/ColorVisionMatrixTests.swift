#if DEBUG
    @testable import DebugDrawerColorVisionPlugin
    import simd
    import Testing

    @Suite
    struct ColorVisionMatrixTests {
        @Test("Protanopia is Machado et al.'s matrix at severity 1.0, row by row")
        func protanopia() {
            let expected = simd_double3x3(rows: [
                SIMD3(0.152286, 1.052583, -0.204868),
                SIMD3(0.114503, 0.786281, 0.099216),
                SIMD3(-0.003882, -0.048116, 1.051998)
            ])

            let actual = ColorVision.Simulation.protanopia.matrix

            #expect(actual == expected)
        }

        @Test("Deuteranopia is Machado et al.'s matrix at severity 1.0, row by row")
        func deuteranopia() {
            let expected = simd_double3x3(rows: [
                SIMD3(0.367322, 0.860646, -0.227968),
                SIMD3(0.280085, 0.672501, 0.047413),
                SIMD3(-0.011820, 0.042940, 0.968881)
            ])

            let actual = ColorVision.Simulation.deuteranopia.matrix

            #expect(actual == expected)
        }

        @Test("Tritanopia is Machado et al.'s matrix at severity 1.0, row by row")
        func tritanopia() {
            let expected = simd_double3x3(rows: [
                SIMD3(1.255528, -0.076749, -0.178779),
                SIMD3(-0.078411, 0.930809, 0.147602),
                SIMD3(0.004733, 0.691367, 0.303900)
            ])

            let actual = ColorVision.Simulation.tritanopia.matrix

            #expect(actual == expected)
        }

        @Test("Grayscale gives every channel the Rec. 709 relative luminance")
        func grayscale() {
            let luminance = SIMD3(0.2126, 0.7152, 0.0722)
            let expected = simd_double3x3(rows: [luminance, luminance, luminance])

            let actual = ColorVision.Simulation.grayscale.matrix

            #expect(actual == expected)
        }

        @Test("Every simulation keeps white and black as they are", arguments: ColorVision.Simulation.allCases)
        func neutralsStay(simulation: ColorVision.Simulation) {
            let white = SIMD3<Double>(1, 1, 1)
            let black = SIMD3<Double>(0, 0, 0)

            let actualWhite = simulation.matrix * white
            let actualBlack = simulation.matrix * black

            #expect(simd_distance(actualWhite, white) < 0.000_01)
            #expect(actualBlack == black)
        }

        @Test("Pure red, green and blue in linear light map to the matrix's columns")
        func primaries() {
            let red = SIMD3<Double>(1, 0, 0)
            let green = SIMD3<Double>(0, 1, 0)
            let blue = SIMD3<Double>(0, 0, 1)
            let expectedRed = SIMD3(0.152286, 0.114503, -0.003882)
            let expectedGreen = SIMD3(0.860646, 0.672501, 0.042940)
            let expectedBlue = SIMD3(-0.178779, 0.147602, 0.303900)

            let actualRed = ColorVision.Simulation.protanopia.matrix * red
            let actualGreen = ColorVision.Simulation.deuteranopia.matrix * green
            let actualBlue = ColorVision.Simulation.tritanopia.matrix * blue

            #expect(actualRed == expectedRed)
            #expect(actualGreen == expectedGreen)
            #expect(actualBlue == expectedBlue)
        }

        @Test("Under protanopia and deuteranopia, pure red and pure green land close in hue: their simulated red-green difference shrinks")
        func redAndGreenConverge() {
            let red = SIMD3<Double>(1, 0, 0)
            let green = SIMD3<Double>(0, 1, 0)
            let original = abs((red.x - red.y) - (green.x - green.y))

            let protanopia = ColorVision.Simulation.protanopia.matrix
            let deuteranopia = ColorVision.Simulation.deuteranopia.matrix
            let protanopiaRed = protanopia * red
            let protanopiaGreen = protanopia * green
            let deuteranopiaRed = deuteranopia * red
            let deuteranopiaGreen = deuteranopia * green
            let protanopiaDifference = abs((protanopiaRed.x - protanopiaRed.y) - (protanopiaGreen.x - protanopiaGreen.y))
            let deuteranopiaDifference = abs((deuteranopiaRed.x - deuteranopiaRed.y) - (deuteranopiaGreen.x - deuteranopiaGreen.y))

            #expect(protanopiaDifference < original / 4)
            #expect(deuteranopiaDifference < original / 4)
        }

        @Test("The simulations cycle in the picker's order, then back to none")
        func cycle() {
            let expected: [ColorVision.Simulation?] = [.protanopia, .deuteranopia, .tritanopia, .grayscale, nil, .protanopia]

            var actual: [ColorVision.Simulation?] = []
            var simulation: ColorVision.Simulation?
            for _ in expected {
                simulation = ColorVision.Simulation.after(simulation)
                actual.append(simulation)
            }

            #expect(actual == expected)
        }

        @Test("Each simulation has a title and a one-line summary")
        func titles() {
            let expected = ["Protanopia", "Deuteranopia", "Tritanopia", "Grayscale"]

            let actual = ColorVision.Simulation.allCases.map(\.title)
            let summaries = ColorVision.Simulation.allCases.map(\.summary)

            #expect(actual == expected)
            #expect(summaries.allSatisfy { !$0.isEmpty && !$0.contains("\n") })
            #expect(Set(summaries).count == summaries.count)
        }
    }
#endif
