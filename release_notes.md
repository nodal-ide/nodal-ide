---
version: 0.19.0
build: 71
---
# Nodal IDE 0.19.0

This is the first Nodal IDE release, published from the independent `nodal-ide` repository.

## Language extensions

- Install native language packs with trusted grammar consent and project activation controls.
- Route extension providers using the active language zone, including mixed-language files.
- Preserve language-zone context in extension results for more accurate editor features.

## Nodal identity and migration

- Launch as Nodal IDE with its independent bundle identity, settings location, and Sparkle update feed.
- Keep CodeEdit installations separate; this release does not update or replace the legacy CodeEdit app.
- Provide first-launch data migration with a recovery prompt for supported user data.

## Notes

- Requires macOS 14 or later.
- This self-distributed build is not notarized; macOS may ask for confirmation on first launch.
