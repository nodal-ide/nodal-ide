import Foundation
import CodeEditLang

struct AppSourceTextProvider: SourceTextProviding {
    private let buffers: [URL: String]
    private let disk: DiskSourceTextProvider

    init(buffers: [URL: String] = [:], disk: DiskSourceTextProvider = DiskSourceTextProvider()) {
        var normalized: [URL: String] = [:]
        normalized.reserveCapacity(buffers.count)
        for (url, text) in buffers {
            normalized[url.standardizedFileURL] = text
        }
        self.buffers = normalized
        self.disk = disk
    }

    @MainActor
    static func snapshot(in workspace: WorkspaceDocument) -> AppSourceTextProvider {
        guard let manager = workspace.editorManager else { return AppSourceTextProvider() }

        var buffers: [URL: String] = [:]
        for editor in manager.flattenedEditors {
            var tabs = Array(editor.tabs)
            if let temporary = editor.temporaryTab { tabs.append(temporary) }
            for tab in tabs {
                guard let document = tab.file.fileDocument, let text = document.content?.string else { continue }
                buffers[tab.file.url.standardizedFileURL] = text
                if let url = document.fileURL {
                    buffers[url.standardizedFileURL] = text
                }
            }
        }
        return AppSourceTextProvider(buffers: buffers)
    }

    func text(for url: URL) -> String? {
        buffers[url.standardizedFileURL] ?? disk.text(for: url)
    }
}
