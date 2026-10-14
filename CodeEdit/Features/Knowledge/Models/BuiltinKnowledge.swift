//
//  BuiltinKnowledge.swift
//  CodeEdit
//
//  The built-in CodeEdit documentation source (in-memory pages).
//

import Foundation

enum BuiltinKnowledge {
    static let sourceID = "com.codeedit.knowledge.builtin"

    static var source: KnowledgeSource {
        KnowledgeSource(
            id: sourceID,
            title: "CodeEdit",
            subtitle: "Built-in documentation",
            storage: .memory(pages: pages),
            index: index
        )
    }

    static let index = KnowledgeIndex(
        title: "CodeEdit",
        subtitle: "Built-in documentation",
        home: "Home.md",
        keywords: ["codeedit", "shortcuts", "extensions", "knowledge"],
        toc: [
            .init(title: "Home", path: "Home.md", children: nil),
            .init(title: "Getting Started", path: nil, children: [
                .init(title: "Opening a project", path: "GettingStarted/Opening.md", children: nil),
                .init(title: "Editing & navigation", path: "GettingStarted/Editing.md", children: nil)
            ]),
            .init(title: "Extensions", path: nil, children: [
                .init(title: "Overview", path: "Extensions/Overview.md", children: nil),
                .init(title: "Authoring a pack", path: "Extensions/Authoring.md", children: nil)
            ]),
            .init(title: "Keyboard Shortcuts", path: "Shortcuts.md", children: nil)
        ]
    )

    static let pages: [String: String] = [
        "Home.md": """
        # CodeEdit

        Welcome to the built-in documentation. Use the table of contents on the left, or search with
        **⌘F**.

        ## What's here

        - **Getting Started** — open a project and find your way around.
        - **Extensions** — add framework knowledge and language features.
        - **Keyboard Shortcuts** — the essentials.

        > Tip: press **⌘⇧K** anywhere to open this Knowledge Base.
        """,

        "GettingStarted/Opening.md": """
        # Opening a project

        - **Open…** (⌘O) opens a file or folder.
        - **Open Quickly** (⇧⌘O) jumps to a file by name.
        - **Command Center** (⌘K) searches files, symbols (`@`) and commands (`>`).

        A project's `.codeedit/settings.json` stores per-project settings, including the language and
        frameworks used for extension activation.
        """,

        "GettingStarted/Editing.md": """
        # Editing & navigation

        | Action | Shortcut |
        |---|---|
        | Go to symbol | ⌥⌘O |
        | Find | ⌘F |
        | Command Center | ⌘K |
        | Open Quickl y | ⇧⌘O |

        Code intelligence (completion, hover, go-to-definition) comes from the built-in engine and from
        installed language extensions.
        """,

        "Extensions/Overview.md": """
        # Extensions

        CodeEdit extensions add knowledge and behaviour without changing the app:

        - **Language packs** are data-only: symbols, signatures and docs (no code).
        - **Providers** are programs (any language) spoken to over JSON-RPC on stdio.
        - **Knowledge bases** are Markdown/HTML docs — like the one you're reading.

        Manage everything from **Extensions ▸ Open Extensions Window**.
        """,

        "Extensions/Authoring.md": """
        # Authoring a pack

        Scaffold a pack with the authoring tool:

        ```sh
        swift run --package-path codeedit-deps/CodeEditLang codeedit-ext init MyPack \\
          --id com.example.mypack --name "My Pack" --language php
        ```

        Validate and package it:

        ```sh
        codeedit-ext validate MyPack
        codeedit-ext pack MyPack
        ```

        See `samples/extensions/README.md` for the full manifest and symbol format.
        """,

        "Shortcuts.md": """
        # Keyboard shortcuts

        | Action | Shortcut |
        |---|---|
        | Command Center | ⌘K |
        | Command Palette | ⇧⌘P |
        | Open Quickly | ⇧⌘O |
        | Go to Symbol | ⌥⌘O |
        | Find | ⌘F |
        | Save | ⌘S |
        | Scratchpad | ⇧⌘N |
        | Knowledge Base | ⌘⇧K |

        Shortcuts are also listed in the **View** and **Navigate** menus.
        """
    ]
}
