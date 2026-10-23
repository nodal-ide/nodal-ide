---
version: 0.22.0
build: 77
---
# Nodal IDE V0.22.0 (build 77)

Nodal IDE 0.22.0 ships the complete local AI Assistant implementation (phases AI2–AI4), adding live streaming with local and OpenAI-compatible providers, workspace-aware BM25 retrieval with clickable citations, secure Keychain API key storage, and workspace-scoped conversation history.

## Features & Improvements

- **Live Streaming & Provider Settings (AI2)**: Integrated `OpenAICompatibleProvider` with real-time SSE streaming, supporting Ollama, LM Studio, and custom local or remote endpoints with local networking permissions (`NSAllowsLocalNetworking`).
- **Secure Keychain Integration**: API keys and secrets are stored exclusively in the macOS Keychain (`CodeEditKeychain`) and are never written to settings, logs, or transcript files.
- **Local BM25 Workspace Retrieval & Citations (AI3)**: Built a local, background BM25 retrieval engine that chunks workspace files and knowledge bases, injecting relevant code context into prompts with stable, clickable `[]` citations.
- **Privacy & Safety Enforcements**: Implemented automatic exclusions for hidden/VCS/build directories, binary files, lockfiles, minified assets, files over 1 MiB, and sensitive/secret paths. Remote provider connections require explicit workspace-context consent.
- **Workspace Conversation History (AI4)**: Added atomic, versioned local transcript storage per workspace under Application Support with retention limits (40 conversations, 90-day cap), chat renaming, deletion, and an optional history-off toggle.
- **Editor & UI Integration**: Added active selection bridging, single-scroll performance optimizations for active streams, and read-only Tree-sitter syntax highlighting for code blocks in completed assistant messages.

## Notes

- Requires macOS 14 or later.
- Local endpoints like Ollama (`http://127.0.0.1:11434/v1`) or LM Studio work out of the box with zero cloud dependencies.