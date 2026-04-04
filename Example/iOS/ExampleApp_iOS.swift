import DebugDrawer
import DebugDrawerAccessibilityPlugin
import DebugDrawerAppInfoPlugin
import DebugDrawerConsolePlugin
import DebugDrawerDiskIOPlugin
import DebugDrawerEnergyPlugin
import DebugDrawerFileBrowserPlugin
import DebugDrawerKeychainPlugin
import DebugDrawerNetworkPlugin
import DebugDrawerPerformancePlugin
import DebugDrawerUserDefaultsPlugin
import SwiftUI

@main
struct DebugDrawerExampleiOSApp: App {
    init() {
        #if DEBUG
            DebugDrawer.shared.installConsole()
            DebugDrawer.shared.installNetwork()
            DebugDrawer.shared.installDiskIO()
            DebugDrawer.shared.installAccessibility()
            DebugDrawer.shared.installPerformance()
            DebugDrawer.shared.installEnergy()
            DebugDrawer.shared.installAppInfo()
            DebugDrawer.shared.installUserDefaults()
            DebugDrawer.shared.installKeychain()
            DebugDrawer.shared.installFileBrowser()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ExampleContentView_iOS()
                .debugAccessibilityOverrides()
                .debugDrawer()
        }
    }
}

struct ExampleContentView_iOS: View {
    @State private var counter = 0
    @State private var text = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Controls") {
                    HStack {
                        Button("Increment") { counter += 1 }
                        Button("Print") { print("Counter: \(counter)") }
                        Button("Reset") { counter = 0 }
                    }
                    .buttonStyle(.bordered)

                    Text("Counter: \(counter)")
                        .font(.title2.monospacedDigit())
                }

                Section("Inputs") {
                    TextField("Sample text field", text: $text)
                    Slider(value: .constant(0.5))
                    Toggle("Toggle", isOn: .constant(true))
                }

                Section("Items") {
                    ForEach(1 ... 20, id: \.self) { i in
                        Label("Item \(i)", systemImage: "circle.fill")
                    }
                }
            }
            .navigationTitle("DebugDrawer Example")
        }
    }
}
