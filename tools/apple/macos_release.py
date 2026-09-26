#!/usr/bin/env python3
"""Generic, config-driven macOS release library: sign, notarize, package,
record release metadata, publish.

No product names live here — a caller (e.g. Stenographer's own
`scripts/release.py`) supplies identities, identifiers, bundle paths and repo
names. Every external command (codesign, notarytool, stapler, ditto,
pkgbuild, productbuild, gh, git, and a caller-supplied `generate_keys` tool)
is invoked through an injected `Runner`, never `subprocess` directly, so
callers can fully unit test a release without touching a keychain, Apple's
notary service, or GitHub.
"""
from __future__ import annotations

import hashlib
import json
import plistlib
import shutil
import subprocess
import tempfile
from dataclasses import dataclass
from pathlib import Path
from typing import Callable, Sequence
from xml.sax.saxutils import escape

Runner = Callable[[list[str]], "subprocess.CompletedProcess[str]"]

_BUNDLE_SUFFIXES = {".framework", ".appex", ".xpc", ".app", ".aiplugin", ".bundle"}
_MACHO_MAGICS = {"cafebabe", "feedfacf", "cffaedfe", "feedface", "cefaedfe"}
_PERMITTED_VIEWER_PERMISSIONS = {"WRITE", "MAINTAIN", "ADMIN"}

#: Filename `build_pkg` gives the component package it builds from the
#: staged app root. `render_distribution`'s `pkg_ref` defaults to the same
#: constant so the two agree by construction instead of by convention.
COMPONENT_PKG = "component.pkg"


@dataclass(frozen=True)
class ReleaseAsset:
    url: str
    size: int
    sha256: str


@dataclass(frozen=True)
class ReleaseEntry:
    version: str
    build: int
    date: str
    minimum_system_version: str
    notes: str
    pkg: ReleaseAsset
    zip: ReleaseAsset


class PreflightError(Exception):
    """Raised by `preflight` listing every failed check, one per line."""


def preflight(
    *,
    identities: list[str],
    notary_profile: str | None,
    releases_json: dict,
    version: str,
    run: Runner,
    require_clean_main: Path | None = None,
    main_branch: str = "main",
    sparkle_account: str | None = None,
    generate_keys: Path | None = None,
    github_repo: str | None = None,
) -> None:
    """Check every release precondition and raise once, listing every
    failure (not just the first), each with the fix that clears it."""
    failures: list[str] = []

    found = run(["security", "find-identity", "-v", "-p", "basic"])
    stdout = found.stdout or ""
    lines = stdout.splitlines()
    for prefix in identities:
        if not any(f"{prefix}:" in line for line in lines):
            failures.append(
                f"missing signing identity '{prefix}' — create it in "
                "Xcode → Settings → Accounts → Manage Certificates"
            )

    if notary_profile:
        history = run(["xcrun", "notarytool", "history", "--keychain-profile", notary_profile])
        if history.returncode != 0:
            failures.append(
                f"notarytool cannot use keychain profile '{notary_profile}' — create it with "
                f"`xcrun notarytool store-credentials {notary_profile}`"
            )

    existing_versions = {r.get("version") for r in releases_json.get("releases", [])}
    if version in existing_versions:
        failures.append(f"{version} is already released — bump the version before releasing")

    if require_clean_main is not None:
        repo = require_clean_main
        status = run(["git", "-C", str(repo), "status", "--porcelain"])
        if status.returncode != 0:
            failures.append(
                f"git status failed in {repo} — {(status.stderr or '').strip() or 'check the repo path'}"
            )
        elif (status.stdout or "").strip():
            failures.append(
                f"{repo} has uncommitted changes — commit or stash them before releasing"
            )

        branch = run(["git", "-C", str(repo), "rev-parse", "--abbrev-ref", "HEAD"])
        if branch.returncode != 0:
            failures.append(
                f"git rev-parse failed in {repo} — {(branch.stderr or '').strip() or 'check the repo path'}"
            )
        else:
            current = (branch.stdout or "").strip()
            if current != main_branch:
                failures.append(
                    f"{repo} is on branch '{current}', not {main_branch} — "
                    f"checkout {main_branch} before releasing"
                )

    if sparkle_account is not None:
        if generate_keys is None:
            failures.append(
                "sparkle_account was given without a generate_keys path — pass "
                "generate_keys=<path to Sparkle's generate_keys tool>"
            )
        else:
            keys = run([str(generate_keys), "--account", sparkle_account, "-p"])
            if keys.returncode != 0:
                failures.append(
                    f"Sparkle account '{sparkle_account}' has no signing key — run "
                    f"`{generate_keys} --account {sparkle_account}` to create one"
                )

    if github_repo is not None:
        auth = run(["gh", "auth", "status"])
        if auth.returncode != 0:
            failures.append("gh is not authenticated — run `gh auth login`")

        view = run(["gh", "repo", "view", github_repo, "--json", "viewerPermission"])
        if view.returncode != 0:
            failures.append(
                f"gh repo view {github_repo} failed — check the repo name and your access"
            )
        else:
            try:
                permission = json.loads(view.stdout or "{}").get("viewerPermission")
            except json.JSONDecodeError:
                permission = None
            if permission not in _PERMITTED_VIEWER_PERMISSIONS:
                failures.append(
                    f"insufficient permission on {github_repo} (have {permission!r}) — "
                    "request write access to the repo"
                )

        tag = f"v{version}"
        released = run(["gh", "release", "view", tag, "--repo", github_repo])
        if released.returncode == 0:
            failures.append(
                f"GitHub release {tag} already exists on {github_repo} — bump the version, or "
                f"delete it with `gh release delete {tag} --repo {github_repo}`"
            )

    if failures:
        raise PreflightError("\n".join(failures))


def _is_bundle_dir(path: Path) -> bool:
    return path.is_dir() and path.suffix in _BUNDLE_SUFFIXES


def _is_macho(path: Path) -> bool:
    try:
        with path.open("rb") as f:
            head = f.read(4)
    except OSError:
        return False
    return head.hex() in _MACHO_MAGICS


def _is_within(path: Path, container: Path) -> bool:
    return path != container and container in path.parents


def signing_order(bundle: Path) -> list[Path]:
    """Nested code deepest-first, the outer bundle last."""
    contents = bundle / "Contents"
    bundle_paths: list[Path] = []
    macho_paths: list[Path] = []
    if contents.exists():
        for path in contents.rglob("*"):
            if _is_bundle_dir(path):
                bundle_paths.append(path)
        for path in contents.rglob("*"):
            if path.is_file() and not any(_is_within(path, b) for b in bundle_paths) and _is_macho(path):
                macho_paths.append(path)

    nested = bundle_paths + macho_paths
    nested.sort(key=lambda p: len(p.relative_to(bundle).parts), reverse=True)
    nested.append(bundle)
    return nested


def sign_bundle(
    bundle: Path,
    *,
    identity: str,
    entitlements: dict[Path, Path],
    runtime: bool,
    timestamp: bool,
    run: Runner,
) -> None:
    for path in signing_order(bundle):
        argv = ["codesign", "--force", "--sign", identity]
        if runtime:
            argv += ["--options", "runtime"]
        if timestamp:
            argv += ["--timestamp"]
        entitlements_path = entitlements.get(path)
        if entitlements_path is not None:
            argv += ["--entitlements", str(entitlements_path)]
        argv.append(str(path))
        result = run(argv)
        if result.returncode != 0:
            raise RuntimeError(result.stderr)

    verify = run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(bundle)])
    if verify.returncode != 0:
        raise RuntimeError(verify.stderr)


def notarize(path: Path, *, profile: str, run: Runner) -> None:
    with tempfile.TemporaryDirectory(prefix="macos_release_notarize_") as tmp:
        target = path
        if path.suffix == ".app":
            target = Path(tmp) / f"{path.stem}.zip"
            zipped = run(["ditto", "-c", "-k", "--keepParent", str(path), str(target)])
            if zipped.returncode != 0:
                raise RuntimeError(zipped.stderr)

        submit = run(
            [
                "xcrun", "notarytool", "submit", str(target),
                "--keychain-profile", profile,
                "--wait", "--output-format", "json",
            ]
        )
        if submit.returncode != 0:
            raise RuntimeError(submit.stderr)

        info = json.loads(submit.stdout)
        if info.get("status") != "Accepted":
            submission_id = info.get("id", "")
            log = run(["xcrun", "notarytool", "log", submission_id, "--keychain-profile", profile])
            raise RuntimeError(log.stdout or log.stderr)

    staple = run(["xcrun", "stapler", "staple", str(path)])
    if staple.returncode != 0:
        raise RuntimeError(staple.stderr)

    validate = run(["xcrun", "stapler", "validate", str(path)])
    if validate.returncode != 0:
        raise RuntimeError(validate.stderr)


def make_update_zip(app: Path, dest: Path, *, run: Runner) -> Path:
    result = run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(dest)])
    if result.returncode != 0:
        raise RuntimeError(result.stderr)
    return dest


def render_distribution(
    *,
    title: str,
    identifier: str,
    version: str,
    pkg_ref: str = COMPONENT_PKG,
    optional_choices: list[tuple[str, str, str, str]],
    installation_check_js: str | None,
    allow_external_scripts: bool = False,
) -> str:
    """Render a productbuild Distribution.xml.

    `optional_choices` items are `(id, title, description, pkg_ref)`: each
    optional choice references its own small component pkg, since Installer
    does not tell postinstall scripts which choices were selected — the
    optional choice installs a marker-file component instead.

    `installation_check_js` is wrapped in a `<![CDATA[…]]>` section so it can
    contain `<`, `&&`, etc. without XML-escaping; it must not itself contain
    the CDATA terminator `]]>`. `allow_external_scripts=True` emits
    `allow-external-scripts="yes"` on `<options>`, required for check/postinstall
    JS that calls `system.run` (e.g. to probe `/usr/bin/python3`).
    """
    if installation_check_js and "]]>" in installation_check_js:
        raise ValueError("installation_check_js must not contain the CDATA terminator ']]>'")

    def esc(text: str) -> str:
        return escape(text, {'"': "&quot;"})

    options_attrs = 'customize="allow" require-scripts="false" hostArchitectures="arm64"'
    if allow_external_scripts:
        options_attrs += ' allow-external-scripts="yes"'

    lines = [
        '<?xml version="1.0" encoding="utf-8"?>',
        '<installer-gui-script minSpecVersion="2">',
        f"    <title>{esc(title)}</title>",
        f"    <options {options_attrs}/>",
        '    <domains enable_localSystem="true"/>',
    ]

    if installation_check_js:
        lines.append('    <installation-check script="pm_install_check();"/>')
        lines.append(
            "    <script><![CDATA[function pm_install_check() { "
            f"{installation_check_js}"
            " }]]></script>"
        )

    lines.append("    <choices-outline>")
    lines.append(f'        <line choice="{esc(identifier)}"/>')
    for choice_id, _title, _description, _pkg in optional_choices:
        lines.append(f'        <line choice="{esc(choice_id)}"/>')
    lines.append("    </choices-outline>")

    lines.append(f'    <choice id="{esc(identifier)}" title="{esc(title)}" visible="false">')
    lines.append(f'        <pkg-ref id="{esc(identifier)}"/>')
    lines.append("    </choice>")

    for choice_id, choice_title, choice_description, _pkg in optional_choices:
        lines.append(
            f'    <choice id="{esc(choice_id)}" title="{esc(choice_title)}" '
            f'description="{esc(choice_description)}" start_selected="false">'
        )
        lines.append(f'        <pkg-ref id="{esc(choice_id)}"/>')
        lines.append("    </choice>")

    lines.append(f'    <pkg-ref id="{esc(identifier)}" version="{esc(version)}">{esc(pkg_ref)}</pkg-ref>')
    for choice_id, _title, _description, choice_pkg in optional_choices:
        lines.append(f'    <pkg-ref id="{esc(choice_id)}">{esc(choice_pkg)}</pkg-ref>')

    lines.append("</installer-gui-script>")
    return "\n".join(lines)


def build_pkg(
    app: Path,
    *,
    identifier: str,
    version: str,
    scripts: Path,
    distribution: str,
    identity: str | None,
    dest: Path,
    run: Runner,
    extra_packages: Sequence[Path] = (),
) -> Path:
    """Build the component pkg from a *staged, non-relocatable* root so that
    Installer always targets the copy at `/Applications`, never "upgrading"
    some other same-bundle-ID copy in place (e.g. a DerivedData build).
    """
    with tempfile.TemporaryDirectory(prefix="macos_release_pkg_") as tmp:
        tmp_path = Path(tmp)

        root = tmp_path / "root"
        root.mkdir()
        staged_app = root / app.name
        stage_result = run(["ditto", str(app), str(staged_app)])
        if stage_result.returncode != 0:
            raise RuntimeError(stage_result.stderr)

        component_plist = tmp_path / "component.plist"
        analyze_result = run(["pkgbuild", "--analyze", "--root", str(root), str(component_plist)])
        if analyze_result.returncode != 0:
            raise RuntimeError(analyze_result.stderr)
        if not component_plist.exists():
            raise RuntimeError(f"pkgbuild --analyze did not write {component_plist}")

        with component_plist.open("rb") as f:
            component_entries = plistlib.load(f)
        for entry in component_entries:
            entry["BundleIsRelocatable"] = False
        with component_plist.open("wb") as f:
            plistlib.dump(component_entries, f)

        component = tmp_path / COMPONENT_PKG
        component_result = run(
            [
                "pkgbuild",
                "--root", str(root),
                "--component-plist", str(component_plist),
                "--install-location", "/Applications",
                "--scripts", str(scripts),
                "--identifier", identifier,
                "--version", version,
                str(component),
            ]
        )
        if component_result.returncode != 0:
            raise RuntimeError(component_result.stderr)

        for extra in extra_packages:
            if extra.name == COMPONENT_PKG:
                raise ValueError(
                    f"extra_packages entry {extra} collides with the reserved component "
                    f"pkg filename {COMPONENT_PKG!r}"
                )
            shutil.copy2(extra, tmp_path / extra.name)

        distribution_path = tmp_path / "Distribution.xml"
        distribution_path.write_text(distribution)

        product_argv = [
            "productbuild",
            "--distribution", str(distribution_path),
            "--package-path", str(tmp_path),
        ]
        if identity:
            product_argv += ["--sign", identity]
        product_argv.append(str(dest))

        product_result = run(product_argv)
        if product_result.returncode != 0:
            raise RuntimeError(product_result.stderr)

    return dest


def asset_for(path: Path, url: str) -> ReleaseAsset:
    digest = hashlib.sha256()
    size = 0
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
            size += len(chunk)
    return ReleaseAsset(url=url, size=size, sha256=digest.hexdigest())


def _asset_dict(asset: ReleaseAsset) -> dict:
    return {"url": asset.url, "size": asset.size, "sha256": asset.sha256}


def _version_tuple(version: str) -> tuple[int, ...]:
    return tuple(int(part) for part in version.split("."))


def merge_release(existing: dict, entry: ReleaseEntry) -> dict:
    """Schema 1: `releases` is always kept sorted newest-first by numeric
    version (descending), regardless of merge order; `latest` is the version
    at the front. Merging an entry whose version already exists replaces
    that entry in place."""
    schema = existing.get("schema")
    if schema != 1:
        raise ValueError(f"unsupported releases schema: {schema!r}")

    releases = [r for r in existing.get("releases", []) if r.get("version") != entry.version]
    releases.append(
        {
            "version": entry.version,
            "build": entry.build,
            "date": entry.date,
            "minimumSystemVersion": entry.minimum_system_version,
            "notes": entry.notes,
            "pkg": _asset_dict(entry.pkg),
            "zip": _asset_dict(entry.zip),
        }
    )
    releases.sort(key=lambda r: _version_tuple(r["version"]), reverse=True)
    return {"schema": 1, "latest": releases[0]["version"], "releases": releases}


def publish_github_release(
    *,
    repo: str,
    tag: str,
    title: str,
    notes_file: Path,
    assets: list[Path],
    run: Runner,
) -> None:
    argv = [
        "gh", "release", "create", tag,
        *[str(asset) for asset in assets],
        "--repo", repo,
        "--title", title,
        "--notes-file", str(notes_file),
    ]
    result = run(argv)
    if result.returncode != 0:
        raise RuntimeError(result.stderr)
