#!/usr/bin/env python3
"""Assert `@agentic-toolkit/adh`'s copied chat contract still matches its source.

`packages/adh/src/persona-chat/chat-types.ts` is a VERBATIM copy of type declarations
that live in `@agenticdevelopertoolkit/chat`. Its own header explains why it is a copy
rather than a dependency: that package is in a different submodule, and this toolkit is
consumed by repos that have neither adh nor that submodule, so a `link:` would resolve
only in a checkout that happens to hold both. Both uses (`persona-chat/index.ts`,
`visitor-chat/sse.ts`) are TYPE-ONLY, so the declarations erase at build time and a
structural copy is exact.

That reasoning holds only while the copy is actually a copy. Nothing about a stale one
is loud: TypeScript keeps compiling — a consumer's real backend simply satisfies a shape
this repo believes is current, and the mismatch surfaces at runtime as a missing field
rather than as a type error. This guard is the thing that makes the duplication safe,
and it is the "must follow" in that header turned into a check.

## What is and isn't drift

Every declaration in the COPY must appear in a source file, byte-for-byte (modulo blank
lines and trailing whitespace). The reverse is deliberately NOT required: the source
declares more than the contract needs — `ChatMode` is chat's own rendering concern — and
copying types this package does not use would be the duplication people fear, not the
narrow one that is justified. A declaration in the copy that no source declares is an
error: this file is not a place to define types.

The parser treats a declaration as running from its `export interface|type NAME` line to
the next top-level `export`. Anything non-exported wedged between two exports therefore
lands inside the preceding declaration and reads as drift — a false alarm, but in the
safe direction, and neither file has ever had such a thing.

Exit codes: 0 in sync · 1 drift · 2 the guard could not find what it checks.
"""

from __future__ import annotations

import difflib
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[3]
COPY = REPO / "packages/web/packages/adh/src/persona-chat/chat-types.ts"
CHAT = REPO / "external/adhsdk/packages/web/packages/chat/src"
SOURCES = (CHAT / "types.ts", CHAT / "backends/types.ts")

DECL = re.compile(r"^export\s+(?:interface|type)\s+(\w+)", re.M)


def declarations(path: Path) -> dict[str, list[str]]:
    """Map each exported type/interface name to its normalized body lines."""
    text = path.read_text()
    starts = [(m.start(), m.group(1)) for m in DECL.finditer(text)]
    out: dict[str, list[str]] = {}
    for i, (pos, name) in enumerate(starts):
        end = starts[i + 1][0] if i + 1 < len(starts) else len(text)
        body = [ln.rstrip() for ln in text[pos:end].splitlines()]
        out[name] = [ln for ln in body if ln]
    return out


def main() -> int:
    missing = [p for p in (COPY, *SOURCES) if not p.is_file()]
    if missing:
        for p in missing:
            print(f"error: not found: {p}", file=sys.stderr)
        if any(p != COPY for p in missing):
            print(
                "\nThe agenticdevelopertoolkit submodule is probably not checked out.\n"
                "Run `./install.sh` (or `git submodule update --init --recursive`) first.",
                file=sys.stderr,
            )
        print("\nverify_chat_types_copy: FAILED TO CHECK.", file=sys.stderr)
        return 2

    source: dict[str, tuple[Path, list[str]]] = {}
    for path in SOURCES:
        for name, body in declarations(path).items():
            source.setdefault(name, (path, body))

    copied = declarations(COPY)
    if not copied:
        print(f"error: no exported declarations parsed from {COPY}", file=sys.stderr)
        print("\nverify_chat_types_copy: FAILED TO CHECK.", file=sys.stderr)
        return 2

    drifted: list[str] = []
    orphans: list[str] = []
    for name, body in copied.items():
        if name not in source:
            orphans.append(name)
            continue
        path, want = source[name]
        if body != want:
            rel = path.relative_to(REPO)
            diff = difflib.unified_diff(
                want, body, fromfile=f"{rel} (source)", tofile="chat-types.ts (copy)",
                lineterm="",
            )
            drifted.append(f"{name}\n" + "\n".join(f"  {ln}" for ln in diff))

    if orphans:
        print(f"{' DECLARED ONLY IN THE COPY ':-^72}")
        for name in orphans:
            print(f"  {name}")
        print(
            "\nchat-types.ts is a copy, not a definition site. Declare these in\n"
            "@agenticdevelopertoolkit/chat and copy them here, or drop them."
        )
    if drifted:
        print(f"{' DRIFTED FROM SOURCE ':-^72}")
        for block in drifted:
            print(block)
        print("\nCopy the source declaration verbatim into chat-types.ts.")

    if orphans or drifted:
        n = len(orphans) + len(drifted)
        print(f"\nverify_chat_types_copy: {n} declaration(s) out of sync.", file=sys.stderr)
        return 1

    print(
        f"verify_chat_types_copy: OK — {len(copied)} copied declaration(s) match "
        f"@agenticdevelopertoolkit/chat."
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
