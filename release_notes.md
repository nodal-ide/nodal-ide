---
version: 0.22.4
build: 81
---
# Nodal IDE V0.22.4 (build 81)

Nodal IDE 0.22.4 ships critical syntax highlighting fixes for Swift and Dart, wires up standalone window actions from the file navigator and external openers, and resolves workspace document completion handlers.

## Fixes & Improvements

- **Tree-sitter Syntax Highlighting Fix**: Fixed a issue where Swift and Dart syntax highlighting was completely missing. `TreeSitterModel` now merges only actual highlight and injection query overlays (`highlights-*`, `injections`, `injections-*`), excluding non-highlight queries (`folds`, `indents`, `locals`, `tags`) that caused compiled query failures.
- **Navigator & External Open Actions**: Wired up "Open in New Window" in the file navigator context menu and added a dedicated external open path in `CodeEditDocumentController` for Finder "Open With", FinderSync, and CLI `--open` flags to launch standalone windows.
- **Workspace Document Lifecycle Fix**: Fixed a bug where opening a file in an existing workspace failed to invoke the `openDocument` completion handler, ensuring opened documents are returned correctly.
- **Expanded Highlight Test Suite**: Added `SwiftHighlightQueryTests` to validate highlighting queries across Swift, PHP, JavaScript, JSX, TypeScript, CSS, HTML, Markdown, and JSON.

## Under the Hood

- Consumes updated local `CodeEditLanguages` packages to support refined language zone abstractions and grammar query filtering.

## Notes

- Requires macOS 14 or later.
- Local endpoints like Ollama (`http://127.0.0.1:11434/v1`) or LM Studio work out of the box with zero cloud dependencies.
- Self-distributed builds are not notarized; macOS may ask for confirmation on first launch.
