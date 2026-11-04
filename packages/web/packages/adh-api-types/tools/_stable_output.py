"""Keep the mtime of a generated file that a rerun reproduced byte-for-byte.

Every generator in this directory rewrites its destination unconditionally: the two
Python ones call `write_text` at the end of a full render, and `gen_schema.py` hands
the path to `openapi-typescript`, which does the same. A rerun that changes nothing
therefore still stamps a fresh mtime — and that is not cosmetic, because these files
are INPUTS to their package's bundle.

`dist_staleness()` in adh's `tools/shared_vendor.py` reads "a source file newer than
the newest thing in dist/" as "this dist is a rollback" — the guard that caught
`b892a088a` shipping a status container which died at startup on an ESM SyntaxError.
adh's `ci.yml` runs `pnpm gen` AFTER `build_shared_deps.py` has built `dist/`, so an
unconditional rewrite makes both backends' vendored-freshness checks fail on a tree
where not one byte has drifted, and hands the reader a remedy that cannot work: the
prescribed `pnpm build:shared` is content-gated, sees no source change, and skips.

So: snapshot the output, and hand the original mtime back to a file the run
reproduced exactly. Content behaviour is unchanged — a real change is still written,
so each generator's `git diff --exit-code` drift gate still fires.

This is the same fix `external/adhsdk/packages/web/packages/themes/scripts/build-tokens.mjs` carries for Style
Dictionary's identical habit, at the one other seam in this workspace where a
generator writes into a package's `src/`.
"""

from __future__ import annotations

import contextlib
import os
from collections.abc import Iterator
from pathlib import Path


@contextlib.contextmanager
def keeping_mtime_if_unchanged(path: Path) -> Iterator[None]:
    """Run the generator, then restore `path`'s mtime if its bytes did not move.

    Wraps the WRITE rather than replacing it, so it works the same whether this
    package's own code holds the pen (`gen_endpoints`, `gen_table_metadata`) or an
    external binary does (`gen_schema` shells out to `openapi-typescript`).

    A first build has nothing to preserve, and an exception from the body propagates
    without a restore — a half-written file must not inherit the timestamp of the
    whole one it replaced.
    """
    try:
        before, stat = path.read_bytes(), path.stat()
    except OSError:
        yield  # No previous output: a first build, and nothing to hand back.
        return
    yield
    try:
        if path.read_bytes() == before:
            os.utime(path, ns=(stat.st_atime_ns, stat.st_mtime_ns))
    except FileNotFoundError:
        pass  # The run removed its own output; there is no mtime to keep.
