# Contributing

Small, focused improvements are welcome. Open an issue before changing storage compatibility or adding a new provider. Please do not upload your memory database, credentials, backups, transcripts, or unredacted screenshots.

## Build

Use macOS 14+, Swift 6.0+ command-line tools, and Python 3.9+:

```sh
./scripts/build.sh
```

The app uses system SwiftUI, AppKit, Charts, and ServiceManagement. There are no Swift package dependencies. `scripts/install.sh` builds, stops the previous Atlas process, and installs the app under `~/Applications`; do not run it during a memory save.

## Run the isolated integration check

With an initialized local claude-mem Chroma runtime:

```sh
python3 scripts/check.py
```

Without claude-mem installed, create a separate Python 3.13 test environment:

```sh
python3.13 -m venv .venv
.venv/bin/python -m pip install -r requirements-test.txt
CHROMA_PYTHON="$PWD/.venv/bin/python" .venv/bin/python scripts/check.py
```

The check uses the committed compatibility schema and synthetic records in temporary SQLite/Chroma stores. It never opens the live memory database or stops the live worker. It verifies FTS, semantic document/query consistency, removed facts, stale edits, rollback, actual undo handling, process-crash recovery, writer-lock ownership, graph links, and JSON/Markdown exports. The default Chroma embedding model may download on the first test run.

CI builds both architectures and runs this check with an isolated runtime. Test dependencies are not application runtime dependencies.

## Documentation screenshots

```sh
./scripts/screenshots.sh
```

This compiles an offscreen renderer for the actual SwiftUI screens and uses the app's read-only synthetic demo. No desktop capture or real memories are used. Images go to `docs/screenshots/`. Keep sample data invented and captions accurate.

## Code map

- `Sources/MemoryAtlas/`: native lifecycle/menu bar, view model, dashboard, browser/editor, graph, settings, and history.
- `Resources/atlas.py`: stdin/stdout JSON bridge, local reads, worker settings, guarded SQLite/Chroma maintenance, recovery, links, and exports.
- `Resources/demo.json`: invented public sample data.
- `scripts/fixtures/`: reviewed upstream schema, without user data.
- `scripts/`: builds, installation, test, packaging, and documentation rendering.

Atlas reads the existing upstream store; do not add an independent memory database or cloud service. Atlas-specific state belongs in its Application Support directory. Keep credentials out of logs and Git.

For edits, preserve IDs and provenance, check stale fingerprints, respect the upstream Chroma writer lock, and keep a durable recovery journal. Any compatibility change needs a review of SQL triggers, hashes, deduplication, vector document IDs/metadata, embeddings, cloud ownership, and worker lifecycle. Extend the isolated check before widening the supported-version guard.

## Pull requests

Explain the user-visible change and how you verified it. For UI changes, include screenshots with synthetic data. For security problems, use the private reporting path in [SECURITY.md](SECURITY.md).

Contributions are accepted under the project's MIT license, except files with an explicitly preserved upstream license. Do not copy upstream code without keeping its applicable notices and license.
