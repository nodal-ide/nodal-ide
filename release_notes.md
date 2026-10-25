---
version: 0.22.2
build: 79
---
# Nodal IDE 0.22.2 (build 79)

Nodal IDE 0.22.2 adds a native editor context-menu entry for the AI Assistant.

## AI Assistant

- Added **Ask Assistant About Selection** to the editor's right-click menu when text is selected.
- The item attaches the exact selection and opens the Assistant panel, focusing the composer without sending.
- The action is routed through the window controller's responder chain, so it follows the editor window that was right-clicked.
- With no selection, the Editor menu and command palette still attach the active file as before.

## Fixes

- The in-app update window now renders release notes directly instead of redirecting to the GitHub release page.
- Release tooling now tolerates transient git lock contention from another git process.

## Under the Hood

- The app now consumes the local `CodeEditSourceEditor` and `CodeEditTextView` forks so the editor exposes an app-owned context-menu hook while keeping Cut/Copy/Paste in the editor.

## Notes

- Requires macOS 14 or later.
- Local endpoints like Ollama (`http://127.0.0.1:11434/v1`) or LM Studio work out of the box with zero cloud dependencies.
