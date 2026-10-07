# Changelog

Versions follow [Semantic Versioning](https://semver.org/). `VERSION` is the source of truth for the app bundle and release archives.

## 0.1.0 — 2026-10-07

First public release of Memory Atlas, an independent native macOS companion to claude-mem.

### Added

- Menu-bar dashboard and macOS login startup.
- Live activity, counts, provider/model, queue, and semantic-index status.
- Search/filter browser for observations and session summaries from the shared local store.
- Metadata knowledge graph with project/concept/file hubs, pan/zoom, keyboard node selection, and manual links.
- Provider, model, reasoning, authentication, and context controls through the existing worker.
- Guarded shared-memory editing with database backups, revision history, undo, stale-write protection, and interrupted-save recovery.
- JSON archives and Obsidian-compatible Markdown exports.
- Read-only synthetic demo and reproducible native documentation screenshots.
- Isolated integration checks, architecture build checks, versioned release archives, and SHA-256 checksums.

### Compatibility and limits

- macOS 14+, separate Apple Silicon and Intel builds; Python 3.9+ required.
- Editing supports local claude-mem 13.29.0 with default local Chroma only.
- Binaries are ad-hoc signed and not Apple notarized.
- No cloud sync, AI relationship inference, subscription allowance meter, or two-way Obsidian sync.
