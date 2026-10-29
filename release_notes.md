---
version: 0.23.3
build: 85
---
# Nodal IDE V0.23.3 (build 85)

## Fixes & Improvements

- CompletionSession.swift owns one session per request: the initial async request, instant fuzzy filtering of the snapshot on every keystroke, and a 50 ms debounced refresh with generation-based stale-response rejection, cancellation on close, and a .pending state so the window doesn't die while a refresh is in flight.
- CompletionMatcher.swift is the single matcher for all providers: prefix → word boundary → substring → subsequence, with stable ties, sortText support, preselect, and a cap. Candidate characters and boundary flags are precomputed once per item, so no nested rescans.
- CompletionItemKind.swift plus defaulted kind/filterText/sortText/preselect/isSnippet on CodeSuggestionEntry — additive, so every existing provider still compiles.
- SuggestionViewModel/SuggestionViewController now drive the session and keep the selected row across refreshes instead of resetting to row 0.
- CompletionMerge.swift holds the tier policy: built-in engine → language server → extension by default, so an enabled PHP native engine stays primary even with Intelephense installed. Language server first and Extension first are selectable.
- LanguageProviderAggregator.swift now queries every routed provider concurrently with a 400 ms per-provider deadline and in-flight coalescing, merges by tier with duplicate suppression and caps, and routes an accepted item back to the provider that produced it (wrapped as AttributedCompletionEntry) rather than routing per session.

## Notes

- Requires macOS 14 or later.
- Local endpoints like Ollama (`http://127.0.0.1:11434/v1`) or LM Studio work out of the box with zero cloud dependencies.
- Self-distributed builds are not notarized; macOS may ask for confirmation on first launch.
