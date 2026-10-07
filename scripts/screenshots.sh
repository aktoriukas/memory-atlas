#!/bin/zsh
set -eu
cd "${0:A:h:h}"
mkdir -p .build docs/screenshots
cp Resources/atlas.py Resources/demo.json .build/
cp scripts/fixtures/claude-mem-13.29.0.sql .build/demo-schema.sql
swiftc -swift-version 5 -D DOCUMENTATION_RENDERER -O Sources/MemoryAtlas/*.swift scripts/screenshots.swift -o .build/render-docs
.build/render-docs --demo --render-docs "$PWD/docs/screenshots"
