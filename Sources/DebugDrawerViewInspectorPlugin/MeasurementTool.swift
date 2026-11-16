#if DEBUG
    import SwiftUI

    // MARK: - SwiftUI result views

    struct AttributeInspectorResultView: View {
        @ObservedObject var controller = InspectorToolController.shared

        var body: some View {
            if !controller.selectedAttributes.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 1) {
                        ForEach(controller.selectedAttributes) { attr in
                            HStack(alignment: .top) {
                                Text(attr.label)
                                    .font(.system(.caption2, weight: .medium))
                                    .foregroundStyle(.secondary)
                                    .frame(width: 80, alignment: .trailing)
                                Text(attr.value)
                                    .font(.system(.caption2, design: .monospaced))
                                    .textSelection(.enabled)
                            }
                            .padding(.vertical, 1)
                        }
                    }
                    .padding(6)
                }
                .frame(maxHeight: 200)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    struct MeasurementResultView: View {
        @ObservedObject var controller = InspectorToolController.shared

        var body: some View {
            if let result = controller.lastMeasureResult {
                HStack(spacing: 12) {
                    measureBadge("H", value: result.horizontal)
                    measureBadge("V", value: result.vertical)
                    measureBadge("D", value: result.diagonal)
                }
                .padding(6)
                .background(Color.primary.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }

        private func measureBadge(_ label: String, value: CGFloat) -> some View {
            VStack(spacing: 0) {
                Text(String(format: "%.0f", value))
                    .font(.system(.callout, design: .monospaced, weight: .bold))
                    .foregroundStyle(.yellow)
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }
#endif
