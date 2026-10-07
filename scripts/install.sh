#!/bin/zsh
set -eu
cd "${0:A:h:h}"
./scripts/build.sh
pkill -x MemoryAtlas || true
for attempt in {1..50}; do
  if ! pgrep -x MemoryAtlas >/dev/null; then break; fi
  sleep 0.1
done
mkdir -p "$HOME/Applications"
ditto "dist/Memory Atlas.app" "$HOME/Applications/Memory Atlas.app"
open "$HOME/Applications/Memory Atlas.app"
