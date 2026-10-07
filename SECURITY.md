# Security

## Supported version

Only the latest Memory Atlas 0.1.x release receives fixes. The editing adapter currently supports local claude-mem 13.29.0. The application is not sandboxed: it needs access to the shared memory store and existing local runtimes. Initial release binaries are ad-hoc signed, not Apple notarized.

## Report privately

Please use [GitHub private vulnerability reporting](https://github.com/aktoriukas/memory-atlas/security/advisories/new). Do not put credentials, memory contents, raw databases, session transcripts, or personal screenshots into a public issue. If private reporting is unavailable, open a minimal issue asking for a private contact without describing the exploit or including sensitive data.

Include the Atlas version, macOS version, claude-mem version, reproduction steps using synthetic data, and the impact. We have no formal response-time guarantee.

## Data boundaries

Atlas opens no HTTP listener and accesses the worker through loopback only. The Python bridge is a trusted local subprocess, not a remote API. Memory text is rendered as text; exports are plaintext snapshots. Existing AI-provider processing and any upstream cloud configuration are separate from Atlas.

The app uses durable edit journals, automatic SQLite backups, FTS triggers, guarded vector reconciliation, and the upstream single-writer lock. It refuses incompatible versions, custom embedding functions, and cloud-synced/replicated writes. Please report any way to bypass those checks or lose data during recovery.
