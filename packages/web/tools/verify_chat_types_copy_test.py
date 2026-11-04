#!/usr/bin/env python3
"""Regression tests for verify_chat_types_copy.py — drift, orphans, and blindness.
Plain asserts, no framework.
Run: python3 packages/web/tools/verify_chat_types_copy_test.py   (exit 0 = pass).

The guard's whole value is the failing case, so each scenario builds a throwaway repo
tree, copies the guard INTO it, and imports it from there — so `REPO = parents[3]` is
exercised for real rather than monkeypatched, and a future path change that breaks
resolution fails here instead of silently checking nothing.
"""
import contextlib
import importlib.util
import io
import shutil
import sys
import tempfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
GUARD = HERE / "verify_chat_types_copy.py"
REAL = HERE.parents[2]  # <repo>/packages/web/tools -> <repo>

REAL_COPY = REAL / "packages/web/packages/adh/src/persona-chat/chat-types.ts"
REAL_CHAT = REAL / "external/adhsdk/packages/web/packages/chat/src"

cases: list[tuple[str, object, object]] = []


def check(name, got, want):
    cases.append((name, got, want))


def build(tmp: Path, *, with_sources: bool = True) -> Path:
    """A minimal tree with the same shape the guard resolves against."""
    copy_dir = tmp / "packages/web/packages/adh/src/persona-chat"
    tools_dir = tmp / "packages/web/tools"
    copy_dir.mkdir(parents=True)
    tools_dir.mkdir(parents=True)
    shutil.copy(GUARD, tools_dir / GUARD.name)
    shutil.copy(REAL_COPY, copy_dir / "chat-types.ts")
    if with_sources:
        chat = tmp / "external/adhsdk/packages/web/packages/chat/src"
        (chat / "backends").mkdir(parents=True)
        shutil.copy(REAL_CHAT / "types.ts", chat / "types.ts")
        shutil.copy(REAL_CHAT / "backends/types.ts", chat / "backends/types.ts")
    return tmp


def run(tmp: Path) -> tuple[int, str]:
    spec = importlib.util.spec_from_file_location(
        f"guard_{tmp.name}", tmp / "packages/web/tools" / GUARD.name
    )
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf), contextlib.redirect_stderr(buf):
        code = module.main()
    return code, buf.getvalue()


def scenario(mutate=None, *, with_sources: bool = True) -> tuple[int, str]:
    with tempfile.TemporaryDirectory() as raw:
        tmp = build(Path(raw), with_sources=with_sources)
        if mutate:
            mutate(
                tmp / "packages/web/packages/adh/src/persona-chat/chat-types.ts",
                tmp / "external/adhsdk/packages/web/packages/chat/src/types.ts",
            )
        return run(tmp)


# The real tree, unmutated, must pass — otherwise every other case below is
# measuring the fixture rather than the guard.
code, out = scenario()
check("in-sync tree passes", code, 0)
check("in-sync tree reports the count", "10 copied declaration(s) match" in out, True)

# Drift in the direction that actually happens: the source grows a field. The copy
# still compiles, so nothing else in the repo notices.
code, out = scenario(
    lambda copy, src: src.write_text(
        src.read_text().replace(
            "  isStreaming?: boolean", "  isStreaming?: boolean\n  editedAt?: Date"
        )
    )
)
check("added source field is drift", code, 1)
check("drift names the declaration", "ChatMessage" in out, True)
check("drift shows the missing line", "editedAt?: Date" in out, True)

# Drift in the other direction: the copy is edited locally.
code, out = scenario(
    lambda copy, src: copy.write_text(copy.read_text().replace("  avatar?: string", ""))
)
check("removed copy field is drift", code, 1)
check("drift names the participant type", "ChatParticipant" in out, True)

# A type declared only in the copy: this file is not a definition site.
code, out = scenario(
    lambda copy, src: copy.write_text(
        copy.read_text() + "\nexport interface LocalOnly {\n  x: string\n}\n"
    )
)
check("copy-only declaration is an orphan", code, 1)
check("orphan is named", "LocalOnly" in out, True)

# The reverse is NOT drift: the source declares more than the contract needs, and
# copying types this package never uses is the duplication worth avoiding.
code, out = scenario(
    lambda copy, src: src.write_text(
        src.read_text() + "\nexport type SourceOnly = 'a' | 'b'\n"
    )
)
check("source-only declaration is fine", code, 0)

# Blindness must be loud: no submodule means the guard checked nothing.
code, out = scenario(with_sources=False)
check("missing submodule exits 2", code, 2)
check("missing submodule explains itself", "submodule" in out, True)
check("missing submodule says it failed to check", "FAILED TO CHECK" in out, True)


failed = [(n, g, w) for n, g, w in cases if g != w]
for name, got, want in failed:
    print(f"FAIL  {name}: got {got!r}, want {want!r}", file=sys.stderr)
print(f"verify_chat_types_copy_test: {len(cases) - len(failed)}/{len(cases)} passed")
sys.exit(1 if failed else 0)
