---
version: 0.24.0
build: 86
---
# Nodal IDE V0.24.0 (build 86)

## New: Change Ribbon

- The editor gutter now marks every line that differs from the last commit: green for added lines, blue for modified blocks, and a red wedge where lines were removed. No more switching to the source control navigator to see what is still pending.
- Colors are derived from the system and adapt to light and dark themes, so the ribbon stays subtle in every theme without needing per-theme configuration.
- The ribbon only draws the lines currently on screen, so scrolling a large file costs the same as scrolling a small one.
- Diffs run off the main thread with one request per file. Results are debounced and generation checked, so a slow diff can never overwrite a newer one, and a file whose content and git status have not changed costs nothing at all.
- Submodules and multi-repo workspaces attribute each open file to the repository that actually owns it.
- Toggle it in Settings → Text Editing → Show Change Ribbon.

## Fixes & Improvements

- Push now works again. Three separate problems were fixed: the push dialog had no view to present from, so the button did nothing; reopening the dialog lost the selected branch and pushed an unnamed ref; and the `--set-upstream`, `--force` and `--tags` flags were silently dropped whenever a remote or branch was unset. Branches without an upstream — the usual case in a submodule — now set their upstream on the first push, and failures surface as an alert instead of returning silently.
- Find: next and previous match, the case-sensitivity toggle, and the other buttons in the find bar are wired to the editor, and the Find menu commands now reach the editor through the responder chain. "Find and Replace" also sends the correct action instead of a hardcoded tag.

## Notes

- Requires macOS 14 or later.
- Local endpoints like Ollama (`http://127.0.0.1:11434/v1`) or LM Studio work out of the box with zero cloud dependencies.
- Self-distributed builds are not notarized; macOS may ask for confirmation on first launch.
