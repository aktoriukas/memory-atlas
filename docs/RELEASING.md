# Releasing

1. Update `VERSION`, `CHANGELOG.md`, and `docs/RELEASE_NOTES.md`; the build script injects the version into the app bundle. Use SemVer (`0.1.1` for compatible fixes, `0.2.0` for pre-1.0 feature/compatibility changes).
2. Run `python3 scripts/check.py`, review the change, regenerate documentation screenshots if needed, and ensure CI passes.
3. Tag the reviewed commit with `v<version>` and push the tag. The Release workflow builds both architectures, packages each app, and uploads them to a **draft release** with checksums.
4. Verify the draft's asset names, checksums, signing status, installation requirements, and release notes. Smoke-test on supported Macs where available, then publish the draft.

For local packaging:

```sh
./scripts/package.sh arm64
./scripts/package.sh x86_64
(cd dist && shasum -a 256 Memory-Atlas-*.zip > SHA256SUMS.txt)
```

Archives contain the application plus `LICENSE.txt`, `THIRD_PARTY_NOTICES.md`, and the preserved upstream schema notices/licenses. Do not include a user's database, settings, credentials, backups, or exports.

The CI token has release-write access only in the publishing job. Pull-request builds do not receive release permissions or signing credentials. If Apple Developer signing/notarization is added later, keep certificates/passwords in protected GitHub secrets and update the installation documentation; do not silently claim ad-hoc builds are notarized.
