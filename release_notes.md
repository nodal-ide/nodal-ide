---
version: 0.20.0
build: 74
---
# Nodal IDE 0.20.0 (build 74)

Nodal IDE 0.20.0 introduces a decentralized extension marketplace and manager, featuring multi-source catalog feeds, secure transactional package installation, multi-project activation controls, and native registry authoring tools.

## Extensions Manager & Marketplace

- **Decentralized source feeds**: Add, refresh, trust, disable, and remove independent `extensions.json` catalog sources using HTTPS or local paths.
- **Discover & search**: Browse extensions across all trusted sources or filter by source, using instant local index search with zero per-keystroke network queries.
- **Transactional installation**: Safe staging and atomic replacement ensure existing installed extensions remain untouched if a download or validation step fails.
- **Archive safety & integrity**: Strict SHA-256 integrity verification, path traversal protection, symlink checks, and entry size limits on all package extractions.
- **Update discovery & offline resilience**: Inspect available updates matching your installed package provenance. Offline modes serve cached catalog data without blocking editor workflows.
- **Provenance tracking**: Installed extensions persist source origin and release integrity metadata to prevent accidental source hijacking during updates.

## Workspace & Project Controls

- **Project-aware activation**: Configure extension enablement per open workspace root without background file scans.
- **Security & consent bounds**: Native Tree-sitter grammars and executable extensions require explicit consent; source trust never auto-approves native code execution.

## Extension Authoring & Registry Tools

- **Create and manage registries**: Initialize local extension registries or clone SSH-backed Git catalog repositories directly inside Nodal.
- **Package & publish workflow**: Validate extension manifests, generate deterministic ZIP archives, calculate SHA-256 hashes, review catalog diffs, and push commits to SSH remotes in one flow.
- **Idempotent publish recovery**: Retain generated commits locally if a Git push fails, protecting active worktrees and enabling single-click retries.

## Notes

- Requires macOS 14 or later.
- Self-distributed builds are not notarized; macOS may ask for confirmation on first launch.