import AppKit
import Foundation

enum ProjectFolderPicker {
    @MainActor
    static func pickFolder(prompt: String = "Add Project") -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = false
        panel.resolvesAliases = true
        panel.prompt = prompt

        return panel.runModal() == .OK ? panel.url : nil
    }
}
