---
version: 0.23.2
build: 84
---
# Nodal IDE V0.23.2 (build 84)

Nodal IDE 0.23.2 is a maintenance update that fixes the symbol hover cards regressed by the 0.23 releases.

## Fixes & Improvements

- **Hover Cards**: Hovering a symbol shows the structured card again — the symbol name with its container or namespace, kind icon, visibility and deprecation badges, a monospaced signature, formatted documentation sections, parameter lists, and syntax-highlighted code. Hover had been reduced to plain text for both PHP and language servers, which flattened the whole card into a single paragraph; language-server hovers also printed raw Markdown code fences and backticks.

## Notes

- Requires macOS 14 or later.
- Local endpoints like Ollama (`http://127.0.0.1:11434/v1`) or LM Studio work out of the box with zero cloud dependencies.
- Self-distributed builds are not notarized; macOS may ask for confirmation on first launch.
