extension KnowledgeRenderer {
    static let stylesheet = """
    :root { color-scheme: light dark; }
    body {
        font: -apple-system-body;
        font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
        margin: 0; padding: 24px 28px 64px;
        background: var(--theme-bg, transparent);
        color: var(--theme-text, -apple-system-label);
        line-height: 1.55;
    }
    article { max-width: 720px; margin: 0 auto; }
    h1, h2, h3, h4 { line-height: 1.25; margin: 1.4em 0 0.5em; }
    h1 {
        font-size: 1.9em;
        border-bottom: 1px solid var(--theme-border, color-mix(in srgb, currentColor 15%, transparent));
        padding-bottom: .3em;
    }
    h2 { font-size: 1.4em; }
    a { color: var(--theme-accent, -apple-system-control-accent); text-decoration: none; }
    a:hover { text-decoration: underline; }
    code {
        font-family: ui-monospace, "SF Mono", Menlo, monospace; font-size: .9em;
        background: color-mix(in srgb, var(--theme-surface, currentColor) 60%, transparent);
        padding: .12em .35em; border-radius: 4px;
    }
    pre {
        background: var(--theme-surface, color-mix(in srgb, currentColor 6%, transparent));
        padding: 12px 14px; border-radius: 8px; overflow-x: auto;
    }
    pre code { background: none; padding: 0; }
    blockquote {
        margin: 1em 0; padding: .2em 1em; color: var(--theme-secondary, -apple-system-secondary-label);
        border-left: 3px solid var(--theme-border, color-mix(in srgb, currentColor 20%, transparent));
    }
    table { border-collapse: collapse; width: 100%; margin: 1em 0; }
    th, td {
        text-align: left; padding: 6px 10px;
        border: 1px solid var(--theme-border, color-mix(in srgb, currentColor 15%, transparent));
    }
    th { background: var(--theme-surface, color-mix(in srgb, currentColor 5%, transparent)); }
    hr {
        border: none;
        border-top: 1px solid var(--theme-border, color-mix(in srgb, currentColor 15%, transparent));
        margin: 2em 0;
    }
    img { max-width: 100%; }
    mark.kh { background: var(--theme-selection, rgba(255, 214, 0, 0.45)); border-radius: 2px; }
    """
}
