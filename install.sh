#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

# Submodules FIRST — packages/web/packages/{features/bitbag,adh} carry `link:` deps that
# point into external/adhsdk. A `link:` to a directory that does not
# exist fails at pnpm-install time, not at build time, so an uninitialised submodule
# breaks the web bootstrap below with an error that names a path rather than a cause.
# Safe to run in a clone made without --recursive, and a no-op once initialised.
if [ -f .gitmodules ]; then
  echo "==> Syncing git submodules"
  git submodule update --init --recursive
fi

# Apple platform: regenerate XcodeGen-backed Xcode projects from project.yml
if command -v xcodegen >/dev/null; then
  echo "==> Regenerating Apple Xcode projects from project.yml"
  for proj in packages/apple/AgenticToolkit packages/apple/AIPlugins packages/apple/AgenticToolkitApp; do
    echo "    $proj"
    ( cd "$proj" && xcodegen generate )
  done
else
  echo "warn: xcodegen not installed — skipping Apple project regeneration."
  echo "      Install it with: brew install xcodegen"
fi

# Web platform: pnpm workspace
if command -v pnpm >/dev/null && command -v node >/dev/null; then
  # The vendored agenticdevelopertoolkit submodule FIRST — packages/adh-ui's `link:` reaches
  # its `ui` package by source, but building/typechecking against it (rather than just
  # running it under the `development` export condition) needs that submodule's OWN dist/
  # and generated theme-data.ts. Neither ships: ADT gitignores dist/, and `themes`'s
  # `build:data` generates theme-data.ts from src/styles/*.css. A fresh clone has neither,
  # so tsc cannot find ADT's .d.ts until this runs once. `pnpm install` + `pnpm run build`
  # are both idempotent (build-tokens/build-theme-data report "unchanged" on a rerun), so
  # this is safe to run on every ./install.sh, not just the first.
  if [ -d external/adhsdk/packages/web ]; then
    echo "==> Installing + building the vendored agenticdevelopertoolkit web workspace"
    ( cd external/adhsdk/packages/web && pnpm install && pnpm run build )
  fi

  echo "==> Installing web workspace deps in packages/web/"
  ( cd packages/web && pnpm install )
else
  echo "warn: node and pnpm are required for the web workspace — skipping."
  echo "      Install them and re-run ./install.sh to bootstrap packages/web/."
fi

cat <<'EOF'

Workspace ready.

Apple:
    open packages/apple/AgenticToolkit.xcworkspace
    # full xcodebuild commands: see .claude/CLAUDE.md

Web:
    cd packages/web && pnpm test
    cd packages/web && pnpm build         # populates dist/ for npm publish

Demo site (websites/site/):
    cd websites/site && npm install && npm run dev
EOF
