#!/usr/bin/env python3
"""Assert which built entries are `'use client'` modules — TRANSITIVELY.

Run from a feature package's root (its `build` script does):

    python3 ../tools/check-directives.py

It reads that package's own `directives` map out of its `package.json`:

    "directives": {
      "index": "client",                                 # must carry the directive
      "parse-path": ["@agentic-toolkit/categories/chain"]  # must not, and may import only these
    }

`"client"` means `dist/<entry>.js` must open with `'use client'`. A LIST means
the opposite — the entry is SERVER-SAFE: neither it nor anything reachable from
it may carry the directive, and the only bare specifiers it may import are the
ones listed. Sibling `@agentic-toolkit/*` specifiers are RESOLVED (through the
package's own `node_modules` symlink and the target's `exports` map, `import`
condition) and walked, so the check crosses package boundaries the same way the
runtime does.

WHY THIS EXISTS AS A CHECK RATHER THAN A COMMENT
------------------------------------------------
`esbuild-plugin-preserve-directives` propagates a chunk's directive to every
entry that imports it, so a package barrel that re-exports one client component
becomes a whole-file client module. Every export in it — a plain string constant
included — then reaches a React Server Component as an opaque CLIENT REFERENCE
rather than as its value. Nothing throws. `segments.indexOf(CHAIN_SEPARATOR)`
compares a string against a reference object, never matches, and returns -1.

That is how research deep links shipped broken. `features/research`'s
`parse-path` entry was correctly built as its own directive-free chunk, but it
imported `CHAIN_SEPARATOR` from the `@agentic-toolkit/categories` BARREL — a
whole-file `'use client'` module — and the toolkit packages are `external` in
this build, so that import survived verbatim into the shipped server chunk and
was resolved inside the caller's RSC. `/<ws>/research/work/-/doc-1` parsed as
the category chain `["work", "-", "doc-1"]` with no document open: every deep
link and every refresh on an open document, silently wrong.

`tsc`, ESLint and vitest cannot see this at all — in all three the import is an
ordinary string, because none of them enforces the client/server boundary — and
`next build` does not see it either, since a Client Component is a legal thing to
be. The only observable difference is the first line of a built file and the
import list beneath it. Hence a check, and hence the transitive walk: asserting
only the entry's own first line would have passed on the broken build.

Sibling of `external/adhsdk/packages/web/packages/landing/tools/check-directives.py`, which asserts the same
property for a package whose entries are declared in its own tsup config.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

PKG = Path.cwd()
DIST = PKG / "dist"
DIRECTIVE = "use client"
SCOPE = "@agentic-toolkit/"

IMPORT_RE = re.compile(
    r"""^\s*(?:import\s[^;]*?from\s*|import\s*|export\s[^;]*?from\s*)["']([^"']+)["']""",
    re.MULTILINE,
)


def first_directive(path: Path) -> str | None:
    """The leading directive of a built ESM file, if it has one."""
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("//"):
            continue
        if len(line) > 1 and line[0] in "'\"":
            quote = line[0]
            end = line.find(quote, 1)
            if end != -1:
                return line[1:end]
        return None
    return None


def imports_of(path: Path) -> list[str]:
    """Every module specifier the built file imports or re-exports from."""
    return IMPORT_RE.findall(path.read_text(encoding="utf-8"))


def resolve_sibling(spec: str, frm: Path) -> tuple[Path, Path] | None:
    """Resolve `@agentic-toolkit/<pkg>[/<sub>]` to (built file, that package's root).

    Deliberately the `import` condition, never `development`: `development`
    points at `src/`, and the question this script asks is about what actually
    ships. Returns None when the package or subpath cannot be resolved — the
    caller reports that, since an unresolvable sibling is not a pass. The root
    comes back too, so bare specifiers found INSIDE the sibling resolve through
    the sibling's own `node_modules`, exactly as they would at runtime.
    """
    rest = spec[len(SCOPE) :]
    name, _, sub = rest.partition("/")
    root = (frm / "node_modules" / SCOPE.rstrip("/") / name).resolve()
    manifest = root / "package.json"
    if not manifest.is_file():
        return None
    exports = json.loads(manifest.read_text(encoding="utf-8")).get("exports", {})
    entry = exports.get(f"./{sub}" if sub else ".")
    if isinstance(entry, dict):
        entry = entry.get("import")
    if not isinstance(entry, str):
        return None
    return (root / entry).resolve(), root


def check_server_safe(entry: str, allowed: list[str]) -> list[str]:
    """Walk everything reachable from a server-safe entry and report violations."""
    failures: list[str] = []
    seen: set[Path] = set()
    queue: list[tuple[Path, Path]] = [((DIST / f"{entry}.js").resolve(), PKG)]
    while queue:
        current, owner = queue.pop()
        if current in seen:
            continue
        seen.add(current)
        if not current.is_file():
            failures.append(f"{current} is imported but does not exist — is the build stale?")
            continue
        if first_directive(current) == DIRECTIVE:
            failures.append(
                f"{current.name} is reachable from dist/{entry}.js and starts with\n"
                f"      '{DIRECTIVE}'. Everything the entry pulls in is resolved inside the\n"
                f"      CALLER — so a server component calling dist/{entry}.js gets client\n"
                f"      references, not values, and comparisons against them silently fail."
            )
            continue
        for spec in imports_of(current):
            if spec.startswith("."):
                queue.append(((current.parent / spec).resolve(), owner))
            elif spec.startswith(SCOPE):
                if spec not in allowed:
                    failures.append(
                        f"{current.name} (reachable from dist/{entry}.js) imports '{spec}',\n"
                        f"      which dist/{entry}.js's allowlist does not name. Add it to the\n"
                        f"      `directives` map in package.json only if it is itself proven\n"
                        f"      server-safe — a package BARREL almost never is."
                    )
                    continue
                resolved = resolve_sibling(spec, owner)
                if resolved is None:
                    failures.append(
                        f"'{spec}' (imported by {current.name}) could not be resolved to a\n"
                        f"      built file. Run the workspace build; an unresolvable sibling\n"
                        f"      cannot be checked and is not a pass."
                    )
                    continue
                # Walk INTO the sibling: the directive is transitive at runtime, so
                # the check has to be too. This is the edge the original bug crossed.
                queue.append(resolved)
            else:
                failures.append(
                    f"{current.name} (reachable from dist/{entry}.js) imports '{spec}'.\n"
                    f"      A server-safe entry may not depend on a runtime package unless the\n"
                    f"      `directives` allowlist names it."
                )
    return failures


def main() -> int:
    manifest = PKG / "package.json"
    if not manifest.is_file():
        sys.exit(f"no package.json at {PKG} — run this from a package root.")
    expected = json.loads(manifest.read_text(encoding="utf-8")).get("directives")
    if not expected:
        sys.exit(f"{manifest} has no `directives` map — nothing to check.")
    if not DIST.is_dir():
        sys.exit(f"dist/ is missing at {DIST} — run the build first.")

    failures: list[str] = []
    for entry, rule in expected.items():
        built = DIST / f"{entry}.js"
        if not built.is_file():
            failures.append(f"{entry}.js was not built (expected at {built})")
            continue
        found = first_directive(built) == DIRECTIVE
        if rule == "client":
            if not found:
                failures.append(
                    f"dist/{entry}.js does NOT start with '{DIRECTIVE}' and must.\n"
                    f"      Its exports hold state or render icons; a server render fails."
                )
            continue
        if found:
            failures.append(
                f"dist/{entry}.js starts with '{DIRECTIVE}' and must not — it is the\n"
                f"      server-safe entry a host RSC CALLS."
            )
            continue
        failures.extend(check_server_safe(entry, list(rule)))

    if failures:
        print("directives: FAILED", file=sys.stderr)
        for f in failures:
            print(f"  ✗ {f}", file=sys.stderr)
        return 1

    summary = ", ".join(
        f"{entry}.js {'client' if rule == 'client' else 'server-safe'}"
        for entry, rule in expected.items()
    )
    print(f"directives: ok ({len(expected)} entries — {summary})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
