#if DEBUG
    import simd

    extension ColorVision.Simulation {
        /// The matrix that maps a color in linear sRGB to the color the simulated eye sees, also
        /// in linear sRGB.
        ///
        /// The dichromacies are Machado, Oliveira and Fernandes's matrices at severity 1.0, from
        /// "A Physiologically-based Model for Simulation of Color Vision Deficiency", IEEE
        /// Transactions on Visualization and Computer Graphics 15(6), 1291–1298, 2009 (the table
        /// at https://www.inf.ufrgs.br/~oliveira/pubs_files/CVD_Simulation/CVD_Simulation.html).
        /// Grayscale is relative luminance, the Rec. 709 (BT.709-6) luma weights, which sRGB's
        /// primaries share, in every row. Each row sums to 1, so white and grays stay as they are.
        var matrix: simd_double3x3 {
            switch self {
            case .protanopia:
                simd_double3x3(rows: [
                    SIMD3(0.152286, 1.052583, -0.204868),
                    SIMD3(0.114503, 0.786281, 0.099216),
                    SIMD3(-0.003882, -0.048116, 1.051998)
                ])
            case .deuteranopia:
                simd_double3x3(rows: [
                    SIMD3(0.367322, 0.860646, -0.227968),
                    SIMD3(0.280085, 0.672501, 0.047413),
                    SIMD3(-0.011820, 0.042940, 0.968881)
                ])
            case .tritanopia:
                simd_double3x3(rows: [
                    SIMD3(1.255528, -0.076749, -0.178779),
                    SIMD3(-0.078411, 0.930809, 0.147602),
                    SIMD3(0.004733, 0.691367, 0.303900)
                ])
            case .grayscale:
                simd_double3x3(rows: [SIMD3(0.2126, 0.7152, 0.0722), SIMD3(0.2126, 0.7152, 0.0722), SIMD3(0.2126, 0.7152, 0.0722)])
            }
        }

        /// The name the picker, the header and the HUD show.
        var title: String {
            switch self {
            case .protanopia: "Protanopia"
            case .deuteranopia: "Deuteranopia"
            case .tritanopia: "Tritanopia"
            case .grayscale: "Grayscale"
            }
        }

        /// What the simulation shows, in a line.
        var summary: String {
            switch self {
            case .protanopia: "No red cones, as in about 1% of men: reds dim and fall in with greens."
            case .deuteranopia: "No green cones, as in about 1% of men: reds and greens look alike."
            case .tritanopia: "No blue cones, which is rare: blues turn teal and yellows pink."
            case .grayscale: "Luminance alone: what is left when hue carries nothing."
            }
        }

        /// The simulation after `simulation` in the order the picker lists them, `nil` after the
        /// last, and the first after `nil`.
        static func after(_ simulation: Self?) -> Self? {
            guard let simulation else { return allCases.first }
            return allCases.drop { $0 != simulation }.dropFirst().first
        }
    }
#endif
