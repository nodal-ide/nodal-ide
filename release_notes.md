---
version: 0.21.0
build: 76
---
# Nodal IDE V0.21.0 (build 76)

Nodal IDE 0.21.0 introduces the foundation for the AI Assistant Chat Panel, providing a native, local-first conversational interface for workspace architecture, code review, debugging, and implementation guidance without background file modifications or autonomous agent execution.

## Features & Improvements

- **AI Assistant Chat Panel (AI0)**: Added a dedicated Assistant tab in the inspector area (`⌥⌘A`) with header controls, scrollable transcript, composer, and session clear/reset capabilities.
- **Inspectable & Non-Agentic Design**: Structured for local RAG-assisted code analysis—designed strictly to explain, review, and suggest implementations without modifying workspace files or running agent loops.
- **Polished Transcript UI**: Added streaming responses, stop execution, retry actions, dark/light/high-contrast macOS materials, and Markdown rendering with copyable code blocks.
- **Local-First Mock Engine**: Integrated a zero-network mock transport layer for offline interface testing and state management before configuring external or local OpenAI-compatible endpoints.
- **Window & Inspector State Restoration**: Maintained persistent inspector width and automatic tab layout restoration across window and session restarts.

## Notes

- Requires macOS 14 or later.
- AI Assistant phase AI0 runs entirely offline with no network requests or API key setup required.