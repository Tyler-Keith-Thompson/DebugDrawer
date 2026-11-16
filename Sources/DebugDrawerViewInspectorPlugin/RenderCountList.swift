#if DEBUG
    import SwiftUI

    /// View types and how many times each rendered, colored by count: green up to 3, orange up to
    /// 10, red above.
    struct RenderCountList: View {
        /// In the order shown, most renders first.
        let entries: [RenderTracker.Entry]

        var body: some View {
            VStack(alignment: .leading, spacing: 1) {
                ForEach(entries) { entry in
                    HStack {
                        Text(entry.id)
                            .font(.system(.caption2, design: .monospaced))
                            .lineLimit(3)
                        Spacer()
                        Text("\(entry.count)")
                            .font(.system(.caption2, design: .monospaced, weight: .bold))
                            .foregroundStyle(Self.color(forCount: entry.count))
                    }
                    .accessibilityElement(children: .combine)
                }
            }
            .padding(4)
            .background(Color.primary.opacity(0.05))
            .cornerRadius(3)
        }

        private static func color(forCount count: Int) -> Color {
            if count <= 3 { return .green }
            if count <= 10 { return .orange }
            return .red
        }
    }
#endif
