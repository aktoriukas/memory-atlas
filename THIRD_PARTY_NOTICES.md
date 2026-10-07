# Third-party acknowledgments

Memory Atlas is an independent companion to [claude-mem](https://github.com/thedotmack/claude-mem), created by [Alex Newman / thedotmack](https://github.com/thedotmack). It is not an official claude-mem product and is not endorsed by Anthropic, OpenAI, or Obsidian.

The native application and original Atlas code are MIT licensed. The compatibility schema in `scripts/fixtures/claude-mem-13.29.0.sql` is derived from claude-mem 13.29.0 and remains under Apache-2.0. Its license and notice are preserved in [docs/licenses](docs/licenses).

Atlas interoperates with an existing claude-mem installation through its local HTTP API, SQLite schema, and Chroma document/locking conventions. It does not bundle the claude-mem worker, Bun, Python, Chroma, embedding models, or the Claude/Codex CLIs. Those components keep their own licenses and terms.

Test-only dependencies are declared in `requirements-test.txt`. Their packages and transitive dependencies are installed separately for development and CI, and are not included in the downloadable application.
