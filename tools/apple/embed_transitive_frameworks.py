#!/usr/bin/env python3
"""Copy transitive .framework bundles next to the app's direct frameworks.

Usage: embed_transitive_frameworks.py <app-bundle> <products-dir>

Starting from the app's main binary, this walks the real Mach-O dependency
graph. Every dependency dyld would resolve *inside the app bundle* is
followed, whichever of the three run-path macros declares it:

- `@rpath/...` is resolved against the referring binary's own `LC_RPATH`
  search paths, in order (`@rpath/*.framework/...` short-circuits to a
  framework name, since the framework is what gets embedded);
- `@loader_path/...` is resolved against the referring binary's directory;
- `@executable_path/...` is resolved against the app's main-executable
  directory.

All three are treated the same way once resolved: if the result lands inside
the bundle and sits inside a `.framework`, that framework is an embed
candidate, and its own binary's dependencies become further roots. If it
lands inside the bundle but is a bare file (the `.debug.dylib` Xcode
substitutes for the app's own code under Debug's "debug dylib" build
acceleration, say), the file itself is traversed. This is what makes the
traversal correct regardless of build configuration: it never depends on
Xcode having pre-populated `Contents/Frameworks`, because it does not start
there -- it starts at the app binary and follows whatever indirection is
actually present.

Each framework name is looked up in <products-dir>, searched at its top
level and in its `PackageFrameworks` subdirectory (where Xcode places Swift
Package Manager package-product frameworks shared by more than one target),
and copied into the app's Frameworks folder. Idempotent: existing copies are
replaced.

Exits non-zero -- copying everything it *could* find along the way, never
partway silently declaring success -- if the app binary or the products
directory is missing, if any wanted framework cannot be found in
<products-dir>, if an embedded framework has no readable binary to traverse,
or if a required (non-weak) dependency that dyld would look for *inside the
bundle* is not there once the walk is done. A reference that resolves
outside the bundle (or has no on-disk file at all, as most system Swift
runtime libraries do once they live in the dyld shared cache) is not an
error -- it is not something this script embeds or can verify by inspecting
the filesystem. Every failure is collected and reported in one run rather
than one at a time. Finding zero frameworks to embed is *not* itself an
error: the traversal always starts at the app binary, so an empty result is
a real answer (the app has no transitive framework dependencies, direct or
indirect), not a symptom of never having looked.
"""
from __future__ import annotations

import os
import shutil
import subprocess
import sys
from pathlib import Path

RUN_PATH_MACROS = ("@rpath", "@loader_path", "@executable_path")


def real_dir(path: Path) -> Path:
    """The directory dyld substitutes for `@loader_path` when it loads `path`:
    the *real* directory the file lives in. A macOS framework bundle is a pile
    of symlinks (`A.framework/A` -> `A.framework/Versions/A/A`), and taking
    `.parent` of the symlink lexically would make a `@loader_path/../../..`
    walk climb out of the wrong directory -- landing on the app bundle rather
    than on `Contents/Frameworks`, where dyld actually looks."""
    return Path(os.path.realpath(path)).parent


def normalize(path: Path) -> Path:
    """Lexically collapse `..`/`.`. Every path this is handed is already
    rooted at a real directory (`real_dir` above, or the app's executable
    directory), so there is no symlink left in the prefix for a lexical walk
    to traverse wrongly -- and the target itself must not be resolved, because
    it usually does not exist yet: embedding it is this script's job."""
    return Path(os.path.normpath(path))


def load_entries(binary: Path) -> list[tuple[str, bool]]:
    """Every dylib this binary loads: the raw install name, and whether the
    load is weak/optional (per `otool -L`'s trailing ", weak)")."""
    out = subprocess.run(["otool", "-L", str(binary)], check=True, capture_output=True, text=True).stdout
    entries: list[tuple[str, bool]] = []
    for line in out.splitlines()[1:]:
        stripped = line.strip()
        path = stripped.split(" (")[0]
        if not path:
            continue
        entries.append((path, stripped.endswith(", weak)")))
    return entries


def rpath_search_dirs(binary: Path, executable_dir: Path) -> list[Path]:
    """LC_RPATH search directories declared by binary, in order, with
    @executable_path (the main app binary's directory, per dyld semantics)
    and @loader_path (this binary's own directory) substituted."""
    out = subprocess.run(["otool", "-l", str(binary)], check=True, capture_output=True, text=True).stdout
    lines = out.splitlines()
    dirs: list[Path] = []
    for i, line in enumerate(lines):
        if line.strip() != "cmd LC_RPATH":
            continue
        for follow in lines[i + 1 : i + 4]:
            stripped = follow.strip()
            if stripped.startswith("path "):
                raw = stripped[len("path ") :].rsplit(" (offset", 1)[0]
                raw = raw.replace("@executable_path", str(executable_dir)).replace("@loader_path", str(real_dir(binary)))
                dirs.append(normalize(Path(raw)))
                break
    return dirs


def framework_binary(framework: Path) -> Path | None:
    candidate = framework / framework.stem
    if candidate.exists():
        return candidate
    versions = framework / "Versions" / "A" / framework.stem
    return versions if versions.exists() else None


def inside(path: Path, app: Path) -> bool:
    return path == app or app in path.parents


def enclosing_framework(path: Path) -> Path | None:
    """The innermost `*.framework` directory containing path, if any. The
    innermost one is the bundle the referenced binary actually belongs to;
    an outer one (frameworks can nest) would name the wrong thing to embed."""
    for parent in path.parents:
        if parent.suffix == ".framework":
            return parent
    return None


def discover(
    binary: Path, executable_dir: Path, app: Path
) -> tuple[set[str], list[Path], list[Path], list[str]]:
    """Classify binary's run-path dependencies into: framework names to embed,
    other Mach-O files inside the app bundle to also traverse (the
    debug-dylib indirection, or anything like it), required files that must
    exist inside the bundle once the walk is done, and entries that were
    expected inside the bundle but could not be found there.

    An `@rpath/...` entry is resolved by searching binary's own LC_RPATH
    list, in order, for the first candidate that exists on disk;
    `@loader_path/...` and `@executable_path/...` need no search -- dyld
    substitutes exactly one directory for each, so the resolution is a single
    path, which is also why they can be *required* to exist rather than
    merely hoped for (see `requirements` below). Three outcomes are *not*
    errors:

    - the entry resolves to a file outside the app bundle (a plain
      OS-provided dylib, e.g. one of SwiftPM's package products declaring a
      literal, non-macro `@rpath` of `/usr/lib/swift`);
    - the entry is weak (optional, shown by otool -L's trailing ", weak)") --
      dyld itself treats a missing weak load as fine, so this script does
      too, rather than enforcing a requirement dyld does not enforce;
    - an `@rpath` entry resolves to a *dangling* symlink in a system search
      directory. A binary here declares both `@executable_path/Frameworks`
      and a literal `/usr/lib/swift`, and non-weakly references
      `libswiftCompatibilitySpan.dylib` -- which `/usr/lib/swift` provides as
      a symlink to `libswiftCore.dylib`, a library that exists only in the
      dyld shared cache and so has no on-disk target. dyld loads it; only a
      link-following `exists()` would call it missing, which is why the
      search below tests `lexists`;
    - an `@rpath` entry is required but every one of this binary's search
      directories is outside the bundle -- meaning no candidate location was
      ever ours to embed, so an on-disk miss (most system Swift runtime
      dylibs live only in the dyld shared cache, with no on-disk file for
      `otool`/`Path.exists()` to find even though they load fine at runtime)
      says nothing about whether we found everything we're responsible for.

    It *is* an error when a required (non-weak) `@rpath` entry cannot be
    found and at least one of the binary's search directories is inside the
    bundle (built from `@executable_path`/`@loader_path`, which always
    resolve under the app) -- that is exactly the shape of the debug-dylib
    bug this traversal exists to close: a same-bundle indirection this script
    failed to find. And it is an error, reported after the walk rather than
    here, when a required `@loader_path`/`@executable_path` entry names a
    location inside the bundle that nothing ever put a file at.
    """
    loader_dir = real_dir(binary)
    search_dirs = rpath_search_dirs(binary, executable_dir)
    bundle_relevant = any(inside(d, app) for d in search_dirs)

    frameworks: set[str] = set()
    other_binaries: list[Path] = []
    requirements: list[Path] = []
    unresolved: list[str] = []

    def take(resolved: Path) -> None:
        """A dependency that lands inside the bundle: embed the framework it
        belongs to, or traverse the file itself."""
        framework = enclosing_framework(resolved)
        if framework is not None:
            frameworks.add(framework.stem)
        elif resolved.exists():
            other_binaries.append(resolved)

    for entry, weak in load_entries(binary):
        if not entry.startswith(RUN_PATH_MACROS):
            continue  # an absolute install name: OS-provided, not ours.
        macro, _, remainder = entry.partition("/")
        if macro == "@rpath":
            if ".framework/" in remainder:
                frameworks.add(remainder.split("/")[0].removesuffix(".framework"))
                continue
            # `lexists`, not `exists`: the question here is only whether dyld
            # would find a candidate at this search directory, and a *dangling*
            # symlink is one. `/usr/lib/swift/libswiftCompatibilitySpan.dylib`
            # is exactly that -- a symlink to `libswiftCore.dylib`, which has no
            # on-disk file because it lives only in the dyld shared cache.
            # Following the link with `exists()` reports "not found" for a
            # dependency that loads perfectly at runtime.
            resolved = next(
                (d / remainder for d in search_dirs if os.path.lexists(d / remainder)),
                None,
            )
            if resolved is not None:
                if inside(normalize(resolved), app):
                    take(normalize(resolved))
                # else: a real file, but outside the bundle (a system dylib) -- not ours to embed or traverse.
            elif bundle_relevant and not weak:
                unresolved.append(f"{entry} (referenced by {binary})")
            # else: unresolved, but either weak (optional -- dyld doesn't require it either) or
            # every search directory was external (OS-managed) -- not an error either way.
            continue

        base = loader_dir if macro == "@loader_path" else executable_dir
        resolved = normalize(base / remainder)
        if not inside(resolved, app):
            continue  # points out of the bundle: OS-managed, same as an external @rpath hit.
        take(resolved)
        if not weak:
            # dyld will look here and nowhere else. Whether the file is there
            # is checked after the walk, once everything has been embedded.
            requirements.append(resolved)

    return frameworks, other_binaries, requirements, unresolved


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    app = Path(os.path.realpath(argv[1]))
    products = Path(argv[2])

    if not products.is_dir():
        print(f"error: products directory not found: {products}", file=sys.stderr)
        return 1

    app_binary = app / "Contents" / "MacOS" / app.stem
    if not app_binary.exists():
        print(f"error: app binary not found: {app_binary}", file=sys.stderr)
        return 1

    frameworks_dir = app / "Contents" / "Frameworks"
    frameworks_dir.mkdir(parents=True, exist_ok=True)

    search_dirs = [products, products / "PackageFrameworks"]
    available = {p.stem: p for d in search_dirs for p in d.glob("*.framework")}
    embedded = {p.stem for p in frameworks_dir.glob("*.framework")}
    executable_dir = real_dir(app_binary)

    visited: set[Path] = set()
    binary_queue: list[Path] = [app_binary]
    missing: set[str] = set()
    unreadable: set[str] = set()
    requirements: set[Path] = set()

    def enqueue_framework_binary(framework: Path, required: bool) -> None:
        """Queue a framework's own binary for traversal. A framework we just
        embedded with no binary we can find is an error, not a silent skip:
        its whole subtree of dependencies would go unwalked, which is the same
        class of defect as never looking -- report success only for work we
        actually did."""
        binary = framework_binary(framework)
        if binary is not None:
            binary_queue.append(binary)
        elif required:
            unreadable.add(framework.name)

    for existing in frameworks_dir.glob("*.framework"):
        enqueue_framework_binary(existing, required=False)

    wanted: set[str] = set()
    unresolved: set[str] = set()

    while binary_queue or wanted:
        for name in sorted(wanted - embedded):
            source = available.get(name)
            if source is None:
                missing.add(name)
                embedded.add(name)
                continue
            target = frameworks_dir / source.name
            if target.exists():
                shutil.rmtree(target)
            shutil.copytree(source, target, symlinks=True)
            embedded.add(name)
            print(f"embedded {name}.framework")
            enqueue_framework_binary(target, required=True)
        wanted = set()

        if not binary_queue:
            break
        binary = binary_queue.pop()
        if binary in visited:
            continue
        visited.add(binary)
        found_frameworks, other_binaries, required_paths, unresolved_entries = discover(
            binary, executable_dir, app
        )
        wanted |= found_frameworks
        for other in other_binaries:
            if other not in visited:
                binary_queue.append(other)
        requirements.update(required_paths)
        unresolved.update(unresolved_entries)

    absent = sorted(str(path) for path in requirements if not path.exists())

    if missing or unresolved or unreadable or absent:
        for name in sorted(missing):
            print(f"error: {name}.framework not found in {products}", file=sys.stderr)
        for entry in sorted(unresolved):
            print(f"error: could not resolve @rpath entry {entry}", file=sys.stderr)
        for name in sorted(unreadable):
            print(f"error: embedded {name} has no binary to traverse", file=sys.stderr)
        for path in absent:
            print(f"error: required dependency missing inside the bundle: {path}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
