#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// Which suite's keys show: Standard, or a suite the host named, such as an app group's.
    struct UserDefaultsSuitePicker: View {
        let suites: [UserDefaultsSuite]
        @Binding var selection: UserDefaultsSuite

        var body: some View {
            // A menu around the picker rather than a menu-style picker, whose label keeps to one
            // line and cuts a long group identifier short at accessibility text sizes; this one
            // wraps.
            Menu {
                Picker("Suite", selection: $selection) {
                    ForEach(suites) { suite in
                        Text(suite.title).tag(suite)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(selection.title)
                        .debugDrawerFont(.code)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    // A Mac's menu button draws its own indicator; iOS's, Mac Catalyst's included,
                    // draws none, so the label carries the picker's.
                    #if os(iOS)
                        Image(systemName: "chevron.up.chevron.down")
                            .imageScale(.small)
                            .accessibilityHidden(true)
                    #endif
                }
            }
            .accessibilityLabel("Suite")
            .accessibilityValue(selection.title)
            .frame(maxWidth: .infinity, alignment: .leading)
            .debugDrawerRowPadding()
        }
    }
#endif
