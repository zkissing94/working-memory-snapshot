import AppKit
import Foundation

enum ProjectFolderPicker {
    @MainActor
    static func pickFolder() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = true
        panel.prompt = "Add Project"

        return panel.runModal() == .OK ? panel.url : nil
    }
}
