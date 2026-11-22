#!/bin/sh
# Bundles the editor's modules and three.js into editor.js, a classic script that runs from file://
cd "$(dirname "$0")" && npm install --no-audit --no-fund >/dev/null && \
    npx esbuild src/main.js --bundle --format=iife --minify --target=chrome100 --outfile=editor.js
