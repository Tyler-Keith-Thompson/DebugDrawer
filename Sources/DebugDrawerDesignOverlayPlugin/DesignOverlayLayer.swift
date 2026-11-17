#if DEBUG
    import SwiftUI

    /// The mockup over the app, from the window's top-leading corner, edge to edge under the safe
    /// area as a screen's mockup is drawn: at its scale, offset and opacity, in its blend.
    ///
    /// It takes no touches or clicks, so the app's controls under it work, except while Move is
    /// on, when a drag anywhere in the window moves it. The mockup is a SwiftUI image with no
    /// platform view, so SwiftUI's hit testing alone decides.
    struct DesignOverlayLayer: View {
        let mockup: Mockup
        let settings: DesignOverlaySettings
        let isMoving: Bool
        /// Called with a drag's translation when it ends.
        let move: (CGSize) -> Void
        @GestureState private var dragTranslation = CGSize.zero

        var body: some View {
            GeometryReader { proxy in
                let size = settings.scale.size(ofMockup: mockup.pixelSize, windowWidth: proxy.size.width)
                Image(decorative: mockup.image, scale: 1)
                    .resizable()
                    .frame(width: size.width, height: size.height)
                    .offset(x: settings.offset.width + dragTranslation.width, y: settings.offset.height + dragTranslation.height)
                    .opacity(settings.opacity)
                    .blendMode(settings.blend.blendMode)
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
            }
            .ignoresSafeArea()
            // The whole window, so a drag can start anywhere while Move is on.
            .contentShape(Rectangle())
            .gesture(drag)
            .allowsHitTesting(isMoving)
            .accessibilityHidden(true)
        }

        private var drag: some Gesture {
            DragGesture()
                .updating($dragTranslation) { value, translation, _ in translation = value.translation }
                .onEnded { move($0.translation) }
        }
    }
#endif
