// The README's Tweaks examples, verbatim, so the README cannot drift from the code. They live here
// rather than in DebugDrawerTests, which links core alone.

#if DEBUG
    import Combine
    import DebugDrawer
    import DebugDrawerTweaksPlugin
    import SwiftUI
    import Testing

    enum Backend: String, CaseIterable {
        case production, staging, local
    }

    enum AppTweaks {
        static let newCheckout = Tweak.toggle("New checkout", key: "newCheckout", default: false)
        static let backend = Tweak.picker("Backend", key: "backend", default: Backend.production)
        static let greeting = Tweak.text("Greeting", key: "greeting", default: "Welcome")
        static let timeout = Tweak.stepper("Timeout (s)", key: "timeout", default: 30, in: 5 ... 120, step: 5)
    }

    struct CheckoutButton: View {
        @State private var isNewCheckout = AppTweaks.newCheckout.value

        var body: some View {
            Button(isNewCheckout ? "Check out (new)" : "Check out") {}
                .onReceive(AppTweaks.newCheckout.publisher) { isNewCheckout = $0 }
        }
    }

    @MainActor
    @Suite("README examples")
    struct READMEExamplesTests {
        @Test("Tweaks")
        func tweaks() {
            DebugDrawer.shared.installTweaks {
                TweakSection("Features") {
                    AppTweaks.newCheckout
                    AppTweaks.greeting
                }
                TweakSection("Server") {
                    AppTweaks.backend
                    AppTweaks.timeout
                }
                TweakSection("Session") {
                    TweakAction("Reset onboarding") {
                        UserDefaults.standard.removeObject(forKey: "hasSeenOnboarding")
                    }
                }
            }

            // Anywhere in the app, in every build:
            let url = switch AppTweaks.backend.value {
            case .production: "https://api.example.com"
            case .staging: "https://staging.example.com"
            case .local: "http://localhost:8080"
            }

            // Leave the shared drawer as the other suites expect it, within this one main-actor turn.
            DebugDrawer.shared.unregisterGlobal(id: "TweaksPlugin")
            _ = CheckoutButton()
            #expect(url == "https://api.example.com")
        }
    }
#endif
