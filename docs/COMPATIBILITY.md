# Compatibility

| Component | Release 0.1.0 |
| --- | --- |
| macOS | 14+ deployment target |
| CPU | Separate Apple Silicon (`arm64`) and Intel (`x86_64`) downloads |
| Swift, for source builds | 6.0+ |
| Python bridge | 3.9+; Homebrew 3.13 recommended |
| claude-mem | Tested with local worker 13.29.0 |
| Editable records | Local observations and session summaries; no raw prompt/provenance edits |
| SQLite | Upstream 13.29.0 schema and FTS5 update triggers |
| Chroma | Local, single collection, default embedding function |
| Chroma helper | Existing cached chroma-mcp 0.2.6 environment; integration checks use chromadb 1.5.9 |
| Cloud sync / replicated records | Editing refused |
| Credentials | Managed by the existing CLI/provider settings, not a separate Atlas account |
| App distribution | Ad-hoc signature; no Apple notarization yet |

Other upstream versions are not approved for editing. The app refuses writes when the worker version differs. Read-only browsing on a newer version still depends on schema compatibility; it is not guaranteed.

Atlas discovers installed worker scripts in the standard Claude/Codex plugin caches and uses the configured local data directory/worker port. Custom deployment layouts, remote workers, and nondefault Python installations are not supported in this first release.

The model shown in the dashboard is the configured override or the detected top-level Codex CLI default. A CLI profile or provider-side model routing can change the actual effective model.

The graph uses metadata links and bounded neighborhoods, not semantic similarity or AI relationship inference. JSON/Markdown export is a snapshot; there is no two-way Obsidian sync or import UI.

The maintenance pipeline is tested against synthetic SQLite/Chroma data, including a forced process exit. Worker stop/start is integration code tied to the supported upstream installation; maintainers should smoke-test it when changing claude-mem compatibility. Apple Silicon is locally exercised; Intel is built and checked in CI, with native UI behavior dependent on the target Mac.
