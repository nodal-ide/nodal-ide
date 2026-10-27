---
version: 0.23.0
build: 82
---
# Nodal IDE V0.23.0 (build 82)

Nodal IDE 0.23.0 introduces an experimental native Find References workspace engine, complete with LSP and native query integration, a dedicated navigator panel, keyboard navigation, and symbol context controls.

## Features & Improvements

- **Find References Engine (RF0–RF4)**: Added a native, multi-provider Find References implementation with single-pass file reading, candidate bounds protection, and cancellation tokens.
- **Dedicated References Navigator Tab (RF2)**: Added a new References tab to the sidebar navigator featuring grouped file lists, target headers, line/column metadata, and distinct iconography for declarations, writes, and reads.
- **Editor & Context Menu Integration**: Bound `⇧F12` to "Find All References" and added an editor right-click menu item alongside the AI Assistant actions.
- **Keyboard Navigation & Instant Reveal**: Single-click or arrow key navigation keeps the References panel open while jumping to source locations in the editor; double-click or `⌘↩` shifts focus directly to the editor buffer.
- **Native PHP & LSP Resolution**: Integrated language server protocol (LSP) and native PHP indexer resolution with support for exact vs. heuristic candidate matches.
- **Bounded & Accessible Results**: Enforced a hard 2,000-row result cap with clear state feedback (`searching`, `results`, `empty`, `partial`, `unsupported`, `failed`, and `stale`), fully labeled for VoiceOver and high-contrast modes.

## Under the Hood

- Introduced `CodeEditLang` shared primitives including `SourceLineIndex`, `SourceTextProviding`, and `PHPReferenceEngine` for O(1) line table lookups and thread-safe reference resolution.

## Notes

- Requires macOS 14 or later.
- Local endpoints like Ollama (`http://127.0.0.1:11434/v1`) or LM Studio work out of the box with zero cloud dependencies.
- Self-distributed builds are not notarized; macOS may ask for confirmation on first launch.
