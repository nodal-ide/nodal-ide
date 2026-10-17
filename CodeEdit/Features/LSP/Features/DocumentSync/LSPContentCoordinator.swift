//
//  LSPContentCoordinator.swift
//  CodeEdit
//
//  Created by Khan Winter on 9/12/24.
//

import AppKit
import AsyncAlgorithms
import CodeEditSourceEditor
import CodeEditTextView
import LanguageServerProtocol

/// This content coordinator forwards content notifications from the editor's text storage to a language service.
///
/// This is a text view coordinator so that it can be installed on an open editor. It is kept as a property on
/// ``CodeFileDocument`` since the language server does all it's document management using instances of that type.
///
/// Language servers expect edits to be sent in chunks (and it helps reduce processing overhead). To do this, this class
/// keeps an async stream around for the duration of its lifetime. The stream is sent edit notifications, which are then
/// chunked into 250ms timed groups before being sent to the ``LanguageServer``.
class LSPContentCoordinator<DocumentType: LanguageServerDocument>: TextViewCoordinator, TextViewDelegate {
    // Required to avoid a large_tuple lint error
    private struct SequenceElement: Sendable {
        let uri: String
        let range: LSPRange
        let string: String
    }

    private var editedRange: LSPRange?
    private var sequenceContinuation: AsyncStream<SequenceElement>.Continuation?
    private var task: Task<Void, Never>?
    /// How often batched edits are flushed to the server. Larger documents sync less often (each flush sends
    /// the full document).
    private var sendInterval: Duration = .milliseconds(250)

    weak var languageServer: LanguageServer<DocumentType>?
    var documentURI: String?

    /// Initializes a content coordinator, and begins an async stream of updates
    init(documentURI: String? = nil, languageServer: LanguageServer<DocumentType>? = nil) {
        self.documentURI = documentURI
        self.languageServer = languageServer

        setUpUpdatesTask()
    }

    func setUp(server: LanguageServer<DocumentType>, document: DocumentType) {
        languageServer = server
        documentURI = document.languageServerURI
    }

    func setUpUpdatesTask() {
        task?.cancel()
        // Create this stream here so it's always set up when the text view is set up, rather than only once on init.
        let stream = AsyncStream { continuation in
            self.sequenceContinuation = continuation
        }

        let interval = sendInterval
        task = Task.detached { [weak self] in
            // Send edit events on the interval chosen for this document's size.
            for await events in stream.chunked(by: .repeating(every: interval, clock: .continuous)) {
                guard !Task.isCancelled, self != nil else { return }
                guard !events.isEmpty, let uri = events.first?.uri else { continue }
                // Errors thrown here are already logged, not much else to do right now.
                try? await self?.languageServer?.documentChanged(
                    uri: uri,
                    changes: events.map {
                        LanguageServer.DocumentChange(replacingContentsIn: $0.range, with: $0.string)
                    }
                )
            }
        }
    }

    func prepareCoordinator(controller: TextViewController) {
        // Each flush re-sends the whole document, so batch less often for large files.
        let length = controller.textView.textStorage.length
        switch length {
        case ..<50_000: sendInterval = .milliseconds(250)
        case ..<300_000: sendInterval = .milliseconds(600)
        default: sendInterval = .milliseconds(1200)
        }
        setUpUpdatesTask()
    }

    /// We grab the lsp range before the content (and layout) is changed so we get correct line/col info for the
    /// language server range.
    func textView(_ textView: TextView, willReplaceContentsIn range: NSRange, with string: String) {
        self.editedRange = textView.lspRangeFrom(nsRange: range)
    }

    func textView(_ textView: TextView, didReplaceContentsIn range: NSRange, with string: String) {
        guard let lspRange = editedRange, let documentURI else {
            return
        }
        self.editedRange = nil
        self.sequenceContinuation?.yield(SequenceElement(uri: documentURI, range: lspRange, string: string))
    }

    func destroy() {
        task?.cancel()
        task = nil
        sequenceContinuation?.finish()
        sequenceContinuation = nil
    }

    deinit {
        destroy()
    }
}
