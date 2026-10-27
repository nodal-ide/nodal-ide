---
version: 0.23.1
build: 83
---
# Nodal IDE V0.23.1 (build 83)

Nodal IDE 0.23.1 is a maintenance update for the 0.23.0 Find References release. It fixes an idle performance regression from the AI assistant's workspace retrieval and restores the app test suite.

## Fixes & Improvements

- **Idle CPU & Memory**: Opening a workspace no longer keeps the app working after launch. The assistant's workspace retrieval no longer saturates two cores for over a minute and no longer drives peak memory to roughly 1.9 GB; the app settles to idle within seconds at about a third less peak memory.
- **Workspace Retrieval Tokenization**: Indexing now splits identifiers in a single pass instead of running a regular expression per identifier and rebuilding character sets per term, making retrieval indexing about 20x faster while producing identical search terms.
- **Repeated Index Builds**: The retrieval index is rebuilt at most once per change to the indexed content instead of twice on every launch.
- **App Test Target**: Removed an unused `ReferencesSession` overload that prevented the test target from compiling, so the suite builds and runs again.

## Notes

- Requires macOS 14 or later.
- Local endpoints like Ollama (`http://127.0.0.1:11434/v1`) or LM Studio work out of the box with zero cloud dependencies.
- Self-distributed builds are not notarized; macOS may ask for confirmation on first launch.
