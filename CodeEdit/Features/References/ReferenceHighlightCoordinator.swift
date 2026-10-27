import AppKit
import Combine
import CodeEditLang
import CodeEditSourceEditor
import CodeEditTextView

/// Emphasizes the current find-references target in one open document.
///
/// This coordinator is installed only in PHP editors whose workspace session is visible, and it emphasizes
/// the document’s own occurrences of the active session target. The session owns the query; this
/// coordinator only renders already-published `EditorReference` rows for its own file, so it never runs a
/// project query.
///
/// Emphasis uses the existing `EmphasisManager` API in one batch per document, with the declaration visually
/// distinct and heuristic name-matches labelled. The coordinator clears on text change, on session
/// staleness, and on destroy.

@MainActor
final class ReferenceHighlightCoordinator: TextViewCoordinator {
    private weak var controller: TextViewController?
    private weak var textView: TextView?
    private weak var emphasisManager: EmphasisManager?
    private weak var workspace: WorkspaceDocument?
    private let fileURL: URL
    private let groupID: String
    private var cancellables = Set<AnyCancellable>()
    private var currentTargetFileURL: URL?
    private var currentKey: String?

    init(
        workspace: WorkspaceDocument?,
        fileURL: URL,
        session: ReferencesSession
    ) {
        self.workspace = workspace
        self.fileURL = fileURL
        self.groupID = "references.session.\(fileURL.path(percentEncoded: false))"
        self.cancellables = []
        observe(session)
    }

    func prepareCoordinator(controller: TextViewController) {
        self.controller = controller
        self.textView = controller.textView
        self.emphasisManager = controller.textView?.emphasisManager
        refreshEmphases()
    }

    func controllerDidDisappear(controller: TextViewController) {
        clearEmphases()
    }

    func destroy() {
        cancellables.removeAll()
        clearEmphases()
        controller = nil
        textView = nil
        emphasisManager = nil
        workspace = nil
    }

    // MARK: - Session observations

    private func observe(_ session: ReferencesSession) {
        session.$target
            .receive(on: DispatchQueue.main)
            .sink { [weak self] target in
                self?.currentTargetFileURL = target?.fileURL.standardizedFileURL
                self?.refreshEmphases()
            }
            .store(in: &cancellables)

        session.$groups
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.refreshEmphases()
            }
            .store(in: &cancellables)
    }

    // MARK: - Text change clears the document’s own emphases

    @MainActor
    func textViewDidChangeText(controller: TextViewController) {
        guard controller.textView == textView else { return }
        clearEmphases()
    }

    // MARK: - Emphasis rendering

    private func refreshEmphases() {
        guard let emphasisManager, let session = workspace?.referencesSession else {
            clearEmphases()
            return
        }

        guard let targetFileURL = currentTargetFileURL ?? session.target?.fileURL.standardizedFileURL,
              targetFileURL == fileURL.standardizedFileURL
        else {
            clearEmphases()
            return
        }

        let refs = session.references(for: fileURL)
        let emphasis = emphases(for: refs)
        currentKey = groupID
        emphasisManager.replaceEmphases(emphasis, for: groupID)
    }

    private func clearEmphases() {
        guard let emphasisManager else { return }
        emphasisManager.removeEmphases(for: groupID)
        currentKey = nil
    }

    private func emphases(for refs: [EditorReference]) -> [Emphasis] {
        refs.map { ref in
            let style: EmphasisStyle
            switch ref.kind {
            case .declaration:
                style = .outline(color: .controlAccentColor)
            case .write:
                style = .outline(color: NSColor.systemOrange, fill: false)
            case .read:
                style = .standard
            case .text:
                style = ref.isHeuristic ? .underline(color: NSColor.systemOrange) : .standard
            }
            return Emphasis(
                range: ref.range,
                style: style,
                inactive: ref.kind != .declaration && !ref.isHeuristic,
                selectInDocument: false
            )
        }
    }
}
