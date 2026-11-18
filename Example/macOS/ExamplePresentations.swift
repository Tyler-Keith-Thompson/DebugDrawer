import AppKit
import SwiftUI

/// Presentations the drawer opens above.
@MainActor
enum ExamplePresentations {
    /// Runs an app-modal NSAlert, which blocks every other window until it is answered.
    static func runAppModalAlert() {
        let alert = NSAlert()
        alert.messageText = "Sample App-Modal Alert"
        alert.informativeText = "Ctrl+D opens the debug drawer above it."
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Launched with -ShowAppModalAlert, runs the app-modal alert once the app has launched, so
    /// the drawer can be checked against it without a hand.
    static func runAppModalAlertIfAsked() {
        guard ProcessInfo.processInfo.arguments.contains("-ShowAppModalAlert") else { return }
        // A task, so launch finishes before the modal session starts.
        Task { @MainActor in runAppModalAlert() }
    }
}

/// Buttons that show a sheet, an alert and an app-modal alert, each of which the drawer opens
/// above.
struct ExamplePresentationButtons: View {
    // Launched with -ShowSampleSheet or -ShowSampleAlert, the window opens with that presentation
    // up, so the drawer can be checked above it without a hand (with -OpenDebugDrawer).
    @State private var isShowingSheet = ProcessInfo.processInfo.arguments.contains("-ShowSampleSheet")
    @State private var isShowingAlert = ProcessInfo.processInfo.arguments.contains("-ShowSampleAlert")
    @AccessibilityFocusState private var isSheetTriggerFocused: Bool
    @AccessibilityFocusState private var isAlertTriggerFocused: Bool

    var body: some View {
        HStack(spacing: 16) {
            Button("Show Sheet") { isShowingSheet = true }
                .accessibilityFocused($isSheetTriggerFocused)
            Button("Show Alert") { isShowingAlert = true }
                .accessibilityFocused($isAlertTriggerFocused)
            Button("Show App-Modal Alert") { ExamplePresentations.runAppModalAlert() }
        }
        // VoiceOver returns to the button that showed the sheet.
        .sheet(isPresented: $isShowingSheet, onDismiss: { isSheetTriggerFocused = true }, content: ExampleSheet.init)
        .alert("Sample Alert", isPresented: $isShowingAlert) {
            // VoiceOver returns to the button that showed the alert.
            Button("OK") { isAlertTriggerFocused = true }
        } message: {
            Text("An alert the app presents on its window.")
        }
    }
}

/// A sheet on the example's window, which the drawer opens above.
struct ExampleSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {
            Text("Sample Sheet")
                .font(.largeTitle)
                .accessibilityAddTraits(.isHeader)
            Button("Done") { dismiss() }
                .keyboardShortcut(.defaultAction)
        }
        .padding(40)
        .frame(width: 420, height: 260)
    }
}
