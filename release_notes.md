---
version: 0.20.1
build: 75
---
# Nodal IDE V0.20.1 (build 75)

Nodal IDE 0.20.1 introduces the native Git Source Provider for the Extension Manager, enabling direct integration with public and private Git extension registries, branch and tag tracking, and offline repository caching.

## Features & Improvements

- **Git Source Provider**: Added native Git provider support for extension registries with support for branch, tag, and commit pinning.
- **Git as Default Provider**: Set the Git provider as the default source engine for extension catalog discovery (`nodal-ide/extensions-registry`).
- **Private & Remote Registry Auth**: Integrated SSH credential handling for cloning and fetching private extension registries without external dependencies.
- **Offline Repository Caching**: Cached Git registry catalogs locally to ensure instant load times and seamless offline availability.

## Notes

- Requires macOS 14 or later.
- First launch may require explicit confirmation if updating from builds with custom source configurations.