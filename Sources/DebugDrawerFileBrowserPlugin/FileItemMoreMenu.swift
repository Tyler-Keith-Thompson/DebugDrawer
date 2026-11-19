#if DEBUG
    import DebugDrawer
    import SwiftUI

    /// More, beside a folder's Refresh or a file's Share…: Import…, Copy Path, Copy Text, Reveal in
    /// Finder, Rename… and Delete, each offered only when its closure is set. In a menu rather than
    /// the action row, where the buttons need two lines in the drawer at its narrowest.
    struct FileItemMoreMenu: View {
        /// The file or folder's name, for the labels of Rename… and Delete.
        let name: String
        /// Asks for a file to import into the folder; `nil` offers no Import….
        var importFile: (() -> Void)?
        /// Copies the item's path.
        let copyPath: () -> Void
        /// Copies a text preview; `nil` offers no Copy Text.
        var copyText: (() -> Void)?
        /// Shows the file in Finder; `nil` offers no Reveal in Finder.
        var revealInFinder: (() -> Void)?
        /// Opens the name editor under the row; `nil` offers no Rename….
        var rename: (() -> Void)?
        /// Opens the delete confirmation under the row; `nil` offers no Delete.
        var delete: (() -> Void)?
        /// Whether a rename or delete is already open under the row, which disables starting
        /// another.
        var isAsking = false

        var body: some View {
            Menu {
                if let importFile {
                    Button("Import…", action: importFile)
                        .accessibilityLabel("Import…")
                        .accessibilityHint("Copies a file you pick into this folder")
                    Divider()
                }
                Button("Copy Path", action: copyPath)
                    .accessibilityLabel("Copy Path")
                    .accessibilityHint("Copies to the clipboard")
                if let copyText {
                    Button("Copy Text", action: copyText)
                        .accessibilityLabel("Copy Text")
                        .accessibilityHint("Copies to the clipboard")
                }
                if let revealInFinder {
                    Button("Reveal in Finder", action: revealInFinder)
                        .accessibilityLabel("Reveal in Finder")
                        .accessibilityHint("Shows the file in a Finder window")
                }
                if rename != nil || delete != nil {
                    Divider()
                }
                if let rename {
                    Button("Rename…", action: rename)
                        .disabled(isAsking)
                        .accessibilityLabel("Rename…")
                        .accessibilityHint("Edits the name of \(name) below")
                }
                // Destructive, so the menu draws it apart and in red; it only opens the
                // confirmation under the row, which deletes.
                if let delete {
                    Button("Delete", role: .destructive, action: delete)
                        .disabled(isAsking)
                        .accessibilityLabel("Delete \(name)")
                        .accessibilityHint("Asks below before deleting")
                }
            } label: {
                Label("More", systemImage: "ellipsis.circle")
                    .labelStyle(.iconOnly)
            }
            .menuStyle(.button)
            .menuIndicator(.hidden)
            .debugDrawerButtonStyle(.borderless)
            .fixedSize()
            .accessibilityLabel("More")
            .help(help)
        }

        /// The tooltip: the actions offered, as "Import, copy, rename or delete".
        private var help: String {
            let actions = [
                importFile.map { _ in "import" },
                "copy",
                revealInFinder.map { _ in "reveal in Finder" },
                rename.map { _ in "rename" },
                delete.map { _ in "delete" }
            ].compactMap(\.self)
            let sentence = actions.formatted(.list(type: .or).locale(Locale(identifier: "en")))
            return sentence.prefix(1).uppercased() + sentence.dropFirst()
        }
    }
#endif
