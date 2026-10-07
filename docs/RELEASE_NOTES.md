Memory Atlas is a native macOS companion to [claude-mem](https://github.com/thedotmack/claude-mem): a menu-bar dashboard to browse, connect, refine, and export your shared AI memories.

### Included

- Live statistics, assistant/project totals, worker/queue/model status.
- Searchable observations and summaries, with filters and provenance.
- Metadata knowledge graph, manual links, and keyboard node selection.
- Provider/model/context settings and existing CLI sign-in flows.
- Guarded edits with backups, undo, stale-write protection, and crash recovery.
- JSON and Obsidian-compatible Markdown exports.
- Login startup and read-only demo with invented memories.

### Install

Download `arm64` for Apple Silicon or `x86_64` for Intel, unzip, and move **Memory Atlas.app** to your Applications folder. Requires macOS 14+, Python 3.9+, and an existing local claude-mem installation. See the [README](https://github.com/aktoriukas/memory-atlas#install) for setup and screenshots.

**Editing is supported only with local claude-mem 13.29.0 and default local Chroma.** Other worker versions are intentionally blocked from editing. Newer upstream versions are not yet guaranteed compatible for browsing.

These initial binaries are **ad-hoc signed, not Apple notarized**. Follow the documented first-launch guidance or build from source. Verify your ZIP with the attached SHA-256 manifest. No private memories, credentials, or user settings are bundled.

The original Atlas code is MIT licensed. The included upstream compatibility schema retains its Apache-2.0 notices. This is an independent community companion, not an official claude-mem, Anthropic, OpenAI, or Obsidian product.
