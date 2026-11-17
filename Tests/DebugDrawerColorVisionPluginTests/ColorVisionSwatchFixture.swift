#if os(macOS)
    import SwiftUI

    /// Content to simulate: fixed sRGB swatches from red to pink, and a pass and a fail told apart
    /// by color alone, drawn by SwiftUI alone, 240 by 96 points.
    struct ColorVisionSwatchFixture: View {
        private let colors: [Color] = [
            Color(.sRGB, red: 0.92, green: 0.20, blue: 0.20), Color(.sRGB, red: 1.00, green: 0.58, blue: 0.00),
            Color(.sRGB, red: 1.00, green: 0.84, blue: 0.00), Color(.sRGB, red: 0.20, green: 0.78, blue: 0.35),
            Color(.sRGB, red: 0.19, green: 0.69, blue: 0.78), Color(.sRGB, red: 0.00, green: 0.48, blue: 1.00),
            Color(.sRGB, red: 0.69, green: 0.32, blue: 0.87), Color(.sRGB, red: 1.00, green: 0.18, blue: 0.33)
        ]

        var body: some View {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 4) {
                    ForEach(colors.indices, id: \.self) { index in
                        RoundedRectangle(cornerRadius: 4).fill(colors[index]).frame(width: 24, height: 36)
                    }
                }
                HStack(spacing: 16) {
                    Circle().fill(Color(.sRGB, red: 0.20, green: 0.78, blue: 0.35)).frame(width: 24, height: 24)
                    Circle().fill(Color(.sRGB, red: 0.92, green: 0.20, blue: 0.20)).frame(width: 24, height: 24)
                }
            }
            .padding(8)
            .frame(width: 240, height: 96, alignment: .topLeading)
            .background(Color.white)
        }
    }
#endif
