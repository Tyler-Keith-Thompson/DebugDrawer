import AppKit
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
import DebugDrawerScreenshotPlugin
import DebugDrawerUserDefaultsPlugin
import DebugDrawerViewInspectorPlugin
import SwiftUI

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindow: NSWindow?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }

    func applicationDidFinishLaunching(_: Notification) {
        #if DEBUG
            DebugDrawer.shared.installConsole()
            DebugDrawer.shared.installNetwork()
            DebugDrawer.shared.installDiskIO()
            DebugDrawer.shared.installViewInspector()
            DebugDrawer.shared.installAccessibility()
            DebugDrawer.shared.installPerformance()
            DebugDrawer.shared.installEnergy()
            DebugDrawer.shared.installScreenshot()
            DebugDrawer.shared.installAppInfo()
            DebugDrawer.shared.installUserDefaults()
            DebugDrawer.shared.installKeychain()
            DebugDrawer.shared.installFileBrowser()
        #endif

        setupMenuBar()
        createMainWindow()
    }

    private func createMainWindow() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DebugDrawer Example"
        window.contentViewController = NSHostingController(rootView: ExampleContentView())
        window.setFrameAutosaveName("DebugDrawerExample")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow = window
    }

    private func setupMenuBar() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appMenuItem.submenu = appMenu
        mainMenu.addItem(appMenuItem)

        NSApp.mainMenu = mainMenu
    }

    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool { true }
}

// MARK: - Example content

struct ExampleContentView: View {
    @State private var selectedItem: String?
    @State private var counter = 0

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItem) {
                Section("Views") {
                    ForEach(["Buttons", "Text Fields", "Sliders", "Toggles", "Images"], id: \.self) { item in
                        Text(item)
                    }
                }
                Section("Data") {
                    ForEach(["Table", "Grid", "Chart", "List"], id: \.self) { item in
                        Text(item)
                    }
                }
            }
            .listStyle(.sidebar)
        } detail: {
            VStack(spacing: 20) {
                Text("DebugDrawer Example")
                    .font(.largeTitle)

                Text("Press Ctrl+D to open the debug drawer")
                    .foregroundStyle(.secondary)

                Divider()

                HStack(spacing: 16) {
                    Button("Increment") { counter += 1 }
                    Button("Print") { print("Counter: \(counter)") }
                    Button("Reset") { counter = 0 }
                }

                Text("Counter: \(counter)")
                    .font(.title2.monospacedDigit())

                HStack {
                    TextField("Sample text field", text: .constant(""))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)

                    Slider(value: .constant(0.5))
                        .frame(width: 150)

                    Toggle("Toggle", isOn: .constant(true))
                }

                Spacer()
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .debugAccessibilityOverrides()
        .debugGrid()
        .debugDrawer()
    }
}
