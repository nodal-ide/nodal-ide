# Hover UX Plan

Replace the plain-text hover tooltip with a rich, semantic hover card that renders PHP docblocks,
LSP Markdown, extension content, and diagnostics consistently. The renderer lives in the editor so every
language provider benefits from the same layout, typography, interaction, and accessibility.

## Goals

- Make PHP hover content production-quality: header, signature, structured docblocks, Markdown, code.
- Keep one renderer for all hover producers: native PHP, LSP, extensions, diagnostics.
- Preserve a safe plain-text fallback for providers that cannot return richer content.
- Match the editor's visual language in light, dark, and high-contrast appearances.
- Keep hover fast, bounded, and non-disruptive to typing and selection.

## Current state

- `HoverInfo` carries only a plain `String` (`CodeEditSourceEditor/.../Hover/HoverDelegate.swift:9`).
- `HoverController` renders one 12pt `NSTextField` with label color and 10pt padding
  (`HoverController.swift:20`, `HoverController.swift:89`).
- PHP hover flattens kind, signature, and raw documentation into plain sections
  (`CodeEditLangPHP/PHPProvider.swift:122`).
- PHPDoc extraction strips comment markers and leading asterisks, then joins plain lines
  (`PHPFileParser.swift:661`).
- LSP hover explicitly removes Markdown syntax before display
  (`LSPLanguageProvider.swift:286`), and the client advertises plaintext-only completion docs
  (`LanguageServer.swift:164`).
- Extension and diagnostic hovers use the same plain-string pipeline
  (`ExtensionLanguageProvider.swift:187`, `HoverModel.swift:92`).

## Tasks

- ✅ **HX1 — Freeze the UX contract.** Visual tokens, content capabilities, layout order, interaction,
  accessibility, fallbacks, limits, and acceptance criteria are frozen below.
- **HX2 — Rich hover model.** Add `HoverContent` and semantic blocks to `CodeEditSourceEditor`; keep the
  plain-string initializer as a compatibility path. Add model tests.
- **HX3 — Renderer shell.** Replace the single label with a stack-based card, scrollable prose area,
  header, badges, separators, dimensions, and dynamic system colors. Add attributed-output tests.
- **HX4 — Markdown renderer.** Parse and style headings, paragraphs, emphasis, inline code, lists, quotes,
  links, and fenced code blocks. Highlight code with the editor theme when a language hint is known.
- **HX5 — PHPDoc parser.** Parse summary, description, and supported tags into a semantic model with
  multiline support and a raw fallback. Add parser tests.
- **HX6 — PHP hover mapping.** Build rich hover documents from `SymbolInfo` + `PHPDocBlock`: header,
  signature, summary, parameters, returns, throws, examples, and metadata. Add provider tests.
- **HX7 — Provider integration.** Enable LSP Markdown hover support, preserve `MarkupContent.kind`, update
  extension and diagnostic hovers, and add mapping/capability tests.
- **HX8 — Interaction and accessibility.** Keep the panel open while the pointer is inside it, add a
  dismissal grace period, Escape-to-close, selection/copy, safe link opening, VoiceOver labels, and
  high-contrast checks.
- **HX9 — Validation and rollout.** Run unit tests, provider tests, performance checks, and the manual QA
  matrix; ship in small PRs across the three repositories.

## HX1 — Frozen UX Contract v1

This section is the contract for the first implementation. Changes require an explicit contract update
before production code changes.

### Scope

In scope:

- Code hovers from the built-in PHP engine, LSP servers, native extensions, and diagnostics.
- Rich Markdown and PHPDoc rendering.
- Selectable text, scrollable long content, and clickable safe links.
- Light, dark, and high-contrast appearances.

Out of scope for v1:

- Hover buttons or actions beyond copy and links.
- Remote images, raw HTML, scripts, Markdown tables, task lists, or footnotes.
- Full `@inheritDoc` resolution.
- User-customizable hover themes.
- Merging hovers from multiple providers; the first provider with content wins, as today.
- Completion popup documentation redesign. The renderer must remain reusable for that follow-up.

### Panel geometry

| Token | Value |
| --- | --- |
| Minimum width | `260pt` |
| Maximum width | `520pt` |
| Maximum height | `420pt` |
| Content inset | `12pt` |
| Section spacing | `10pt` |
| Corner radius | `8pt` |
| Anchor gap | `6pt` |
| Border | `1pt` separator, visible in high contrast |
| Background | `.popover` visual-effect material |

- Prefer the content's natural width up to `520pt`; do not force a fixed width.
- Scroll the whole card body when height exceeds `420pt`.
- Place above the hovered range, flip below when there is no room, then clamp to the visible screen.
- Do not cover the hovered identifier when an alternative placement exists.

### Typography

| Role | Style |
| --- | --- |
| Symbol title | System `13pt`, semibold, label color |
| Kind / container | System `11pt`, regular, secondary label |
| Badge | System `10pt`, semibold, tinted capsule |
| Body | System `12pt`, regular, line height `17pt` |
| Secondary metadata | System `11pt`, regular, secondary label |
| Signature | Monospaced `12pt`, regular, line height `18pt` |
| Code block | Monospaced `12pt`, regular, line height `18pt` |
| Inline code | Monospaced `11.5pt`, label color |

- Body paragraphs use `4pt` spacing after each paragraph.
- Lists use `16pt` leading indent and `2pt` item spacing.
- H1/H2/H3 map to `15pt`/`14pt`/`13pt`, semibold; body hierarchy must not exceed the symbol title.
- Signatures and code blocks use the editor font when available, otherwise the system monospaced font.
- Inline code and code blocks use the editor theme for syntax colors when available.

### Semantic color tokens

| Token | Default |
| --- | --- |
| `background` | `.popover` material |
| `text` | `labelColor` |
| `secondaryText` | `secondaryLabelColor` |
| `separator` | `separatorColor` |
| `link` | `linkColor` |
| `accent` | `controlAccentColor` |
| `codeBackground` | `quaternaryLabelColor` at low opacity over the panel |
| `codeBorder` | `separatorColor` |
| `warning` | `systemOrange` |
| `error` | `systemRed` |
| `success` | `systemGreen` |
| `info` | `systemBlue` |

- Use dynamic `NSColor` values only; no fixed hex values.
- Symbol tints are semantic, not PHP-specific: type, callable, value, namespace.
- Meaning must never depend on color alone; pair color with an icon or label.
- Respect Increase Contrast and Reduce Transparency where practical.

### Content order

1. Header: kind icon/tint, symbol name, container, badges.
2. Notice: deprecated, diagnostic severity, or other warning.
3. Signature block.
4. Summary and description.
5. Parameters.
6. Returns.
7. Throws.
8. Examples.
9. See also.
10. Metadata: `@since`, `@author`, unknown tags.
11. Optional footer: source file and line.

Omit empty sections without leaving extra spacing.

### Header contract

- Always show the symbol name and kind.
- Show the container or fully qualified name when it is not redundant.
- Badges may include `deprecated`, `static`, `abstract`, `readonly`, `internal`, and visibility.
- Use an SF Symbol per semantic kind; the icon must not be the only kind indicator.
- Diagnostic hovers use a severity label (`Error`, `Warning`, `Info`, `Hint`) and icon instead of a symbol
  kind.

### Signature contract

- Render signatures in a monospaced code block with a subtle background and `8pt` inner padding.
- Use editor syntax colors when available; otherwise keep the signature label color.
- Do not wrap mid-token. Wrap at punctuation boundaries when possible.
- Keep the full signature visible before documentation.
- LSP code blocks and PHPDoc examples follow the same code-block style.

### Markdown contract

Supported in v1:

- Headings H1–H3.
- Paragraphs and hard line breaks.
- Bold, italic, strikethrough.
- Inline code.
- Fenced code blocks with optional language hints.
- Ordered and unordered lists, including nested indentation.
- Blockquotes.
- Thematic breaks.
- Links.
- Inline `{@link}` and `{@see}` converted to links when a target is available.

Render rules:

- Fenced code blocks render as full-width cards, not inline colored text.
- Language hints select syntax highlighting; unknown languages fall back to monospaced text.
- Links use link color and an underline. Only `http`, `https`, and `mailto` are clickable.
- Unsupported constructs render as plain text rather than disappearing.
- If Markdown parsing fails, show the original text in the plain-text style.
- Do not load remote resources.

### PHPDoc contract

Supported tags in v1:

| Tag | Presentation |
| --- | --- |
| `@param [type] $name description` | Definition row: monospaced name, type chip, description |
| `@return type description` | Definition row: type chip, description |
| `@throws type description` | Warning-toned definition row |
| `@var type description` | Definition row for properties/constants |
| `@deprecated [description]` | Notice below the header |
| `@see target` | Link or monospaced reference |
| `@example [description]` | Optional description plus code block |
| `@since version` | Muted metadata |
| `@author name` | Muted metadata |
| Unknown tags | Muted `@tag` line plus preserved content |

Rules:

- Summary is the first paragraph; remaining prose is the description.
- Preserve Markdown inside summaries and descriptions.
- Support multiline tag descriptions and code fences inside `@example`.
- Parse types without truncating generics, unions, intersections, or callable signatures.
- Display types as inline code.
- Duplicate tags render in source order.
- Missing or malformed tags must not discard the rest of the documentation.
- `@inheritDoc` / `{@inheritdoc}` are displayed as a muted note in v1.

### Interaction contract

- Keep the existing `350ms` dwell before requesting content.
- Show the card only after content is available; never show an empty card.
- Keep the card visible while the pointer is over the anchor range or the card.
- Start a `200ms` dismissal timer when the pointer leaves both; cancel it if the pointer returns.
- Close immediately on Escape, text edit, editor scroll, window resign, or a new hover target.
- Scrolling inside the card must not dismiss it.
- Clicking a link opens it externally and must not change the editor selection.
- Text selection and copy are allowed. The card may become key for selection without activating the app.
- Clicking inside the card must not move the editor caret.
- No entrance animation; avoid motion that competes with typing.

### Accessibility contract

- Expose the card as a group with a useful label such as `Hover: <symbol name>`.
- VoiceOver must read header, signature, body, and definitions in visual order.
- Links expose their destination and are keyboard reachable when the card is key.
- Selection and copy work with standard macOS shortcuts.
- High-contrast mode retains readable borders, code backgrounds, and badge contrast.
- Color is never the only carrier of severity, deprecation, or symbol kind.

### Limits and fallbacks

- Raw hover content is capped at `32KB`; beyond that, truncate and append `Documentation truncated`.
- Maximum rendered height is `420pt`; use scrolling, not content removal.
- No unbounded caches. Rendering must not trigger network requests.
- Target: warm hover content visible within `150ms` after dwell; no single main-thread render over `16ms`.
- Plain-text providers keep their current content and receive the same panel chrome.
- Unknown Markdown or PHPDoc constructs render literally; they are never silently dropped.

### Provider mapping

| Source | V1 content type |
| --- | --- |
| Native PHP | Structured document |
| LSP `MarkupContent.kind == markdown` | Markdown |
| LSP `MarkupContent.kind == plaintext` | Plain text |
| LSP `MarkedString` with language | Code block or Markdown fenced code |
| Extension RPC | Plain text |
| Diagnostics | Structured notice document |

### Fixture matrix

The initial implementation must cover:

- PHP function with summary, description, every supported tag, and a code example.
- PHP method and property with missing documentation.
- PHP class/interface/trait/enum/constant hovers.
- PHPDoc with multiline tags, generics, union types, and malformed tags.
- LSP Markdown with headings, lists, links, inline code, and fenced code.
- LSP plaintext and language-tagged `MarkedString`.
- Extension plain text.
- Error, warning, info, and hint diagnostics.
- Overlong documentation, very long signature, and wide code line.
- Dark, light, and high-contrast appearances.
- Missing screen space above and below the anchor.

### Acceptance criteria for HX1

- [x] Visual tokens, dimensions, typography, and color roles are defined.
- [x] Markdown and PHPDoc support is explicitly bounded.
- [x] Content order and empty-section behavior are defined.
- [x] Interaction, dismissal, selection, links, and focus behavior are defined.
- [x] Accessibility and contrast requirements are defined.
- [x] Safety, size, truncation, and performance limits are defined.
- [x] Provider mapping and fixture matrix are defined.
- [x] No production code changed as part of freezing the contract.

## Status

- ✅ **HX1** — UX contract frozen in this document. No production code changed.
- ⬜ **HX2** — next: rich hover model in `CodeEditSourceEditor`.

## Notes / decisions

- Prefer a semantic content model over prebuilt `NSAttributedString` from providers. Providers stay
  language-focused; the editor owns rendering and theming.
- Keep `HoverInfo(contents:)` as a compatibility bridge so existing providers do not break during the
  migration.
- Use Foundation's Markdown parser and the existing Tree-sitter quick-highlight path; no new dependency.
- Use system semantic colors and editor theme colors; do not hard-code appearance-specific colors.
- Ship in small slices, one repository at a time: `CodeEditSourceEditor` model → renderer → Markdown,
  `CodeEditLang` PHPDoc + PHP mapping, then `CodeEdit` provider integration and polish.
