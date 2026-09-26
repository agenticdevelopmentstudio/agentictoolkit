#!/usr/bin/env python3
"""Tests for macos_release.py.

Every external command (codesign, notarytool, stapler, ditto, pkgbuild,
productbuild, gh, git, generate_keys) is asserted through an injected
`Runner` recorder — nothing here ever touches a keychain, Apple's notary
service, or GitHub.

Run: python3 -m pytest tools/apple/macos_release_test.py -q
"""
from __future__ import annotations

import hashlib
import json
import plistlib
import subprocess
import xml.etree.ElementTree as ET
from pathlib import Path

import pytest

import macos_release as mr


def recorder():
    """A run() that records every call and, for a `pkgbuild --analyze` call,
    also writes a minimal component plist to the path it was asked to
    analyze into — standing in for what real pkgbuild would write, since
    `build_pkg` reads that file back to flip `BundleIsRelocatable`."""
    calls: list[list[str]] = []

    def run(argv: list[str]) -> subprocess.CompletedProcess:
        calls.append(argv)
        if argv[0] == "pkgbuild" and "--analyze" in argv:
            with Path(argv[-1]).open("wb") as f:
                plistlib.dump([{"RootRelativeBundlePath": "A.app", "BundleIsRelocatable": True}], f)
        return subprocess.CompletedProcess(argv, 0, "", "")

    return calls, run


# ---------------------------------------------------------------------------
# merge_release
# ---------------------------------------------------------------------------


def test_merge_release_puts_newest_first_and_sets_latest():
    a = mr.ReleaseEntry(
        "2.154.0", 411, "2026-09-27T00:00:00Z", "26.0", "notes/2.154.0.md",
        mr.ReleaseAsset("u1", 1, "s1"), mr.ReleaseAsset("u2", 2, "s2"),
    )
    b = mr.ReleaseEntry(
        "2.155.0", 412, "2026-09-28T00:00:00Z", "26.0", "notes/2.155.0.md",
        mr.ReleaseAsset("u3", 3, "s3"), mr.ReleaseAsset("u4", 4, "s4"),
    )
    doc = mr.merge_release(mr.merge_release({"schema": 1, "latest": None, "releases": []}, a), b)
    assert doc["latest"] == "2.155.0"
    assert [r["version"] for r in doc["releases"]] == ["2.155.0", "2.154.0"]
    assert doc["releases"][0]["minimumSystemVersion"] == "26.0"
    assert doc["releases"][0]["pkg"] == {"url": "u3", "size": 3, "sha256": "s3"}


def test_merge_release_replaces_same_version():
    e = mr.ReleaseEntry("2.154.0", 411, "d", "26.0", "n", mr.ReleaseAsset("u", 1, "s"), mr.ReleaseAsset("u", 1, "s"))
    doc = mr.merge_release(mr.merge_release({"schema": 1, "latest": None, "releases": []}, e), e)
    assert len(doc["releases"]) == 1


def test_merge_release_refuses_unknown_schema():
    with pytest.raises(ValueError):
        mr.merge_release({"schema": 2, "releases": []}, None)


def test_merge_release_sorts_numerically_not_by_merge_order():
    # Merging the newer release FIRST, then an older one, must not leave the
    # older one at the front just because it was merged in last.
    newer = mr.ReleaseEntry(
        "2.155.0", 412, "2026-09-28T00:00:00Z", "26.0", "n2",
        mr.ReleaseAsset("u3", 3, "s3"), mr.ReleaseAsset("u4", 4, "s4"),
    )
    older = mr.ReleaseEntry(
        "2.154.1", 411, "2026-09-27T00:00:00Z", "26.0", "n1",
        mr.ReleaseAsset("u1", 1, "s1"), mr.ReleaseAsset("u2", 2, "s2"),
    )
    doc = mr.merge_release(mr.merge_release({"schema": 1, "latest": None, "releases": []}, newer), older)
    assert doc["latest"] == "2.155.0"
    assert [r["version"] for r in doc["releases"]] == ["2.155.0", "2.154.1"]


def test_merge_release_sorts_2_10_ahead_of_2_9():
    # A lexical sort would put "2.9.0" first and make /downloads/latest
    # redirect to an older build.
    def entry(version: str, build: int) -> mr.ReleaseEntry:
        return mr.ReleaseEntry(
            version, build, "d", "26.0", f"notes/{version}.md",
            mr.ReleaseAsset("u", 1, "s"), mr.ReleaseAsset("u", 1, "s"),
        )

    empty = {"schema": 1, "latest": None, "releases": []}
    doc = mr.merge_release(mr.merge_release(empty, entry("2.10.0", 2)), entry("2.9.0", 1))
    assert doc["latest"] == "2.10.0"
    assert [r["version"] for r in doc["releases"]] == ["2.10.0", "2.9.0"]


# ---------------------------------------------------------------------------
# preflight
# ---------------------------------------------------------------------------


def test_preflight_refuses_already_released_version_and_lists_all_failures():
    def run(argv):
        if argv[:2] == ["security", "find-identity"]:
            return subprocess.CompletedProcess(argv, 0, '  1) ABC "Apple Development: X (T)"\n', "")
        return subprocess.CompletedProcess(argv, 1, "", "no profile")

    with pytest.raises(mr.PreflightError) as exc:
        mr.preflight(
            identities=["Developer ID Application", "Developer ID Installer"],
            notary_profile="p", version="2.154.0",
            releases_json={"schema": 1, "latest": "2.154.0", "releases": [{"version": "2.154.0"}]},
            run=run,
        )
    msg = str(exc.value)
    assert "Developer ID Application" in msg and "Developer ID Installer" in msg
    assert "notarytool" in msg and "2.154.0 is already released" in msg


def test_preflight_require_clean_main_dirty_tree_fails(tmp_path):
    repo = tmp_path / "repo"

    def run(argv):
        if argv[:2] == ["security", "find-identity"]:
            return subprocess.CompletedProcess(argv, 0, "", "")
        if argv[:2] == ["git", "-C"] and "status" in argv:
            return subprocess.CompletedProcess(argv, 0, "M some/file\n", "")
        if argv[:2] == ["git", "-C"] and "rev-parse" in argv:
            return subprocess.CompletedProcess(argv, 0, "main\n", "")
        return subprocess.CompletedProcess(argv, 0, "", "")

    with pytest.raises(mr.PreflightError) as exc:
        mr.preflight(
            identities=[], notary_profile=None,
            releases_json={"schema": 1, "releases": []}, version="1.0",
            run=run, require_clean_main=repo,
        )
    assert "uncommitted changes" in str(exc.value) and str(repo) in str(exc.value)


def test_preflight_require_clean_main_wrong_branch_fails(tmp_path):
    repo = tmp_path / "repo"

    def run(argv):
        if argv[:2] == ["security", "find-identity"]:
            return subprocess.CompletedProcess(argv, 0, "", "")
        if argv[:2] == ["git", "-C"] and "status" in argv:
            return subprocess.CompletedProcess(argv, 0, "", "")
        if argv[:2] == ["git", "-C"] and "rev-parse" in argv:
            return subprocess.CompletedProcess(argv, 0, "feature\n", "")
        return subprocess.CompletedProcess(argv, 0, "", "")

    with pytest.raises(mr.PreflightError) as exc:
        mr.preflight(
            identities=[], notary_profile=None,
            releases_json={"schema": 1, "releases": []}, version="1.0",
            run=run, require_clean_main=repo,
        )
    assert "not main" in str(exc.value) and "feature" in str(exc.value)


def test_preflight_require_clean_main_git_status_failure_is_a_failure_not_clean(tmp_path):
    repo = tmp_path / "repo"

    def run(argv):
        if argv[:2] == ["security", "find-identity"]:
            return subprocess.CompletedProcess(argv, 0, "", "")
        if argv[:2] == ["git", "-C"] and "status" in argv:
            return subprocess.CompletedProcess(argv, 128, "", "not a git repository")
        if argv[:2] == ["git", "-C"] and "rev-parse" in argv:
            return subprocess.CompletedProcess(argv, 0, "main\n", "")
        return subprocess.CompletedProcess(argv, 0, "", "")

    with pytest.raises(mr.PreflightError) as exc:
        mr.preflight(
            identities=[], notary_profile=None,
            releases_json={"schema": 1, "releases": []}, version="1.0",
            run=run, require_clean_main=repo,
        )
    msg = str(exc.value)
    assert "git status failed" in msg and str(repo) in msg
    assert "has uncommitted changes" not in msg


def test_preflight_require_clean_main_respects_main_branch_param(tmp_path):
    repo = tmp_path / "repo"

    def run(argv):
        if argv[:2] == ["security", "find-identity"]:
            return subprocess.CompletedProcess(argv, 0, "", "")
        if argv[:2] == ["git", "-C"] and "status" in argv:
            return subprocess.CompletedProcess(argv, 0, "", "")
        if argv[:2] == ["git", "-C"] and "rev-parse" in argv:
            return subprocess.CompletedProcess(argv, 0, "release\n", "")
        return subprocess.CompletedProcess(argv, 0, "", "")

    # Would fail against the "main" default; passing main_branch="release"
    # makes the current branch the accepted one.
    mr.preflight(
        identities=[], notary_profile=None,
        releases_json={"schema": 1, "releases": []}, version="1.0",
        run=run, require_clean_main=repo, main_branch="release",
    )  # no raise


def test_preflight_sparkle_account_fails(tmp_path):
    generate_keys = tmp_path / "generate_keys"

    def run(argv):
        if argv[:2] == ["security", "find-identity"]:
            return subprocess.CompletedProcess(argv, 0, "", "")
        if argv[0] == str(generate_keys):
            return subprocess.CompletedProcess(argv, 1, "", "no key on keychain")
        return subprocess.CompletedProcess(argv, 0, "", "")

    with pytest.raises(mr.PreflightError) as exc:
        mr.preflight(
            identities=[], notary_profile=None,
            releases_json={"schema": 1, "releases": []}, version="1.0",
            run=run, sparkle_account="acct1", generate_keys=generate_keys,
        )
    msg = str(exc.value)
    assert "Sparkle account 'acct1'" in msg and str(generate_keys) in msg


def test_preflight_sparkle_account_without_generate_keys_fails():
    def run(argv):
        return subprocess.CompletedProcess(argv, 0, "", "")

    with pytest.raises(mr.PreflightError) as exc:
        mr.preflight(
            identities=[], notary_profile=None,
            releases_json={"schema": 1, "releases": []}, version="1.0",
            run=run, sparkle_account="acct1",
        )
    assert "generate_keys" in str(exc.value)


def test_preflight_github_repo_fails_when_not_authenticated():
    def run(argv):
        if argv[:2] == ["security", "find-identity"]:
            return subprocess.CompletedProcess(argv, 0, "", "")
        if argv[:2] == ["gh", "auth"]:
            return subprocess.CompletedProcess(argv, 1, "", "not logged in")
        if argv[:3] == ["gh", "repo", "view"]:
            return subprocess.CompletedProcess(argv, 0, json.dumps({"viewerPermission": "WRITE"}), "")
        return subprocess.CompletedProcess(argv, 0, "", "")

    with pytest.raises(mr.PreflightError) as exc:
        mr.preflight(
            identities=[], notary_profile=None,
            releases_json={"schema": 1, "releases": []}, version="1.0",
            run=run, github_repo="me/repo",
        )
    assert "gh auth login" in str(exc.value)


def test_preflight_github_repo_fails_on_insufficient_permission():
    def run(argv):
        if argv[:2] == ["security", "find-identity"]:
            return subprocess.CompletedProcess(argv, 0, "", "")
        if argv[:2] == ["gh", "auth"]:
            return subprocess.CompletedProcess(argv, 0, "", "")
        if argv[:3] == ["gh", "repo", "view"]:
            return subprocess.CompletedProcess(argv, 0, json.dumps({"viewerPermission": "READ"}), "")
        return subprocess.CompletedProcess(argv, 0, "", "")

    with pytest.raises(mr.PreflightError) as exc:
        mr.preflight(
            identities=[], notary_profile=None,
            releases_json={"schema": 1, "releases": []}, version="1.0",
            run=run, github_repo="me/repo",
        )
    assert "insufficient permission" in str(exc.value) and "me/repo" in str(exc.value)


def test_preflight_github_repo_fails_when_tag_already_released():
    def run(argv):
        if argv[:2] == ["security", "find-identity"]:
            return subprocess.CompletedProcess(argv, 0, "", "")
        if argv[:2] == ["gh", "auth"]:
            return subprocess.CompletedProcess(argv, 0, "", "")
        if argv[:3] == ["gh", "repo", "view"]:
            return subprocess.CompletedProcess(argv, 0, json.dumps({"viewerPermission": "WRITE"}), "")
        if argv[:3] == ["gh", "release", "view"]:
            return subprocess.CompletedProcess(argv, 0, "", "")  # tag exists
        return subprocess.CompletedProcess(argv, 0, "", "")

    with pytest.raises(mr.PreflightError) as exc:
        mr.preflight(
            identities=[], notary_profile=None,
            releases_json={"schema": 1, "releases": []}, version="1.0",
            run=run, github_repo="me/repo",
        )
    msg = str(exc.value)
    assert "v1.0" in msg and "already exists" in msg and "me/repo" in msg


def test_preflight_passes_when_everything_succeeds(tmp_path):
    repo = tmp_path / "repo"
    generate_keys = tmp_path / "generate_keys"

    def run(argv):
        if argv[:2] == ["security", "find-identity"]:
            return subprocess.CompletedProcess(
                argv, 0,
                '1) X "Developer ID Application: Y (T)"\n1) X "Developer ID Installer: Y (T)"\n', "",
            )
        if argv[:2] == ["xcrun", "notarytool"]:
            return subprocess.CompletedProcess(argv, 0, "", "")
        if argv[:2] == ["git", "-C"] and "status" in argv:
            return subprocess.CompletedProcess(argv, 0, "", "")
        if argv[:2] == ["git", "-C"] and "rev-parse" in argv:
            return subprocess.CompletedProcess(argv, 0, "main\n", "")
        if argv[0] == str(generate_keys):
            return subprocess.CompletedProcess(argv, 0, "", "")
        if argv[:2] == ["gh", "auth"]:
            return subprocess.CompletedProcess(argv, 0, "", "")
        if argv[:3] == ["gh", "repo", "view"]:
            return subprocess.CompletedProcess(argv, 0, json.dumps({"viewerPermission": "ADMIN"}), "")
        if argv[:3] == ["gh", "release", "view"]:
            return subprocess.CompletedProcess(argv, 1, "", "release not found")  # tag not yet released
        return subprocess.CompletedProcess(argv, 0, "", "")

    mr.preflight(
        identities=["Developer ID Application", "Developer ID Installer"],
        notary_profile="p", releases_json={"schema": 1, "releases": []}, version="1.0",
        run=run, require_clean_main=repo, sparkle_account="acct1",
        generate_keys=generate_keys, github_repo="me/repo",
    )  # no raise


# ---------------------------------------------------------------------------
# signing_order / sign_bundle
# ---------------------------------------------------------------------------


def test_signing_order_is_deepest_first_bundle_last(tmp_path):
    app = tmp_path / "A.app"
    for p in [
        "Contents/Frameworks/F.framework",
        "Contents/PlugIns/W.appex",
        "Contents/PlugIns/W.appex/Contents/Frameworks/G.framework",
    ]:
        (app / p).mkdir(parents=True)
    (app / "Contents/MacOS").mkdir(parents=True)
    (app / "Contents/MacOS/d").write_bytes(b"\xcf\xfa\xed\xfe")  # Mach-O magic
    order = mr.signing_order(app)
    assert order[-1] == app
    assert order.index(app / "Contents/PlugIns/W.appex/Contents/Frameworks/G.framework") < \
        order.index(app / "Contents/PlugIns/W.appex")


def _write_plist(path: Path, executable: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("wb") as f:
        plistlib.dump({"CFBundleExecutable": executable}, f)


def _write_macho(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"\xcf\xfa\xed\xfe")  # Mach-O magic `signing_order` detects


def _build_fake_sparkle_app(tmp_path: Path) -> Path:
    """A.app embedding a Sparkle.framework laid out like the real thing: a
    versioned `Autoupdate` helper that is a bare Mach-O (not the framework's
    own main executable), an `Installer.xpc` and `Downloader.xpc` under
    `XPCServices`, a nested `Updater.app`, and a `Versions/Current` symlink
    pointing at the real version directory (`B`)."""
    app = tmp_path / "A.app"
    _write_macho(app / "Contents/MacOS/A")
    _write_plist(app / "Contents/Info.plist", "A")

    framework = app / "Contents/Frameworks/Sparkle.framework"
    versions_b = framework / "Versions/B"

    _write_macho(versions_b / "Sparkle")  # the framework's own main executable
    _write_plist(versions_b / "Resources/Info.plist", "Sparkle")

    _write_macho(versions_b / "Autoupdate")  # bare helper, NOT the main executable

    _write_macho(versions_b / "XPCServices/Installer.xpc/Contents/MacOS/Installer")
    _write_plist(versions_b / "XPCServices/Installer.xpc/Contents/Info.plist", "Installer")

    _write_macho(versions_b / "XPCServices/Downloader.xpc/Contents/MacOS/Downloader")
    _write_plist(versions_b / "XPCServices/Downloader.xpc/Contents/Info.plist", "Downloader")

    _write_macho(versions_b / "Updater.app/Contents/MacOS/Updater")
    _write_plist(versions_b / "Updater.app/Contents/Info.plist", "Updater")

    (framework / "Versions/Current").symlink_to("B")
    return app


def test_signing_order_signs_bare_helper_executable_inside_nested_framework(tmp_path):
    # Sparkle's Autoupdate is a bare Mach-O helper inside Sparkle.framework
    # that is not the framework's own main executable (CFBundleExecutable is
    # "Sparkle", not "Autoupdate"). The old within-any-nested-bundle check
    # excluded it entirely, so it kept its ad-hoc signature and notarization
    # rejected the app. It — and every nested bundle — must now be signed,
    # ordered before the framework, which is ordered before the app.
    app = _build_fake_sparkle_app(tmp_path)
    framework = app / "Contents/Frameworks/Sparkle.framework"
    order = mr.signing_order(app)

    autoupdate = framework / "Versions/B/Autoupdate"
    installer_xpc = framework / "Versions/B/XPCServices/Installer.xpc"
    downloader_xpc = framework / "Versions/B/XPCServices/Downloader.xpc"
    updater_app = framework / "Versions/B/Updater.app"

    assert autoupdate in order
    for item in (autoupdate, installer_xpc, downloader_xpc, updater_app):
        assert order.index(item) < order.index(framework)
    assert order.index(framework) < order.index(app)
    assert order[-1] == app

    # The framework's own main executable must not be signed a second time
    # as a loose Mach-O — only the framework bundle itself signs it.
    assert framework / "Versions/B/Sparkle" not in order


def test_signing_order_breaks_depth_ties_by_path(tmp_path):
    # rglob yields filesystem-traversal order; the tiebreak keeps the
    # order identical on every machine.
    app = _build_fake_sparkle_app(tmp_path)
    b = app / "Contents/Frameworks/Sparkle.framework/Versions/B"
    order = mr.signing_order(app)

    assert order.index(b / "XPCServices/Downloader.xpc") < order.index(b / "XPCServices/Installer.xpc")
    assert order.index(b / "Autoupdate") < order.index(b / "Updater.app")


def test_signing_order_resolves_versions_current_symlink_without_duplicates(tmp_path):
    app = _build_fake_sparkle_app(tmp_path)
    framework = app / "Contents/Frameworks/Sparkle.framework"
    order = mr.signing_order(app)

    # No path appears twice, and no symlink — nor anything reached only by
    # walking through one, such as Versions/Current — is ever signed.
    assert len(order) == len(set(order))
    assert all(not p.is_symlink() for p in order)
    assert framework / "Versions/Current" not in order
    assert sum(1 for p in order if p.name == "Autoupdate") == 1


def test_sign_bundle_preserves_entitlements_on_unmapped_nested_items(tmp_path):
    app = _build_fake_sparkle_app(tmp_path)
    framework = app / "Contents/Frameworks/Sparkle.framework"
    downloader_xpc = framework / "Versions/B/XPCServices/Downloader.xpc"
    downloader_ent = tmp_path / "downloader.entitlements"
    downloader_ent.write_bytes(plistlib.dumps({"com.apple.security.network.client": True}))

    calls, run = recorder()
    mr.sign_bundle(
        app, identity="Developer ID Application: X (T)",
        entitlements={downloader_xpc: downloader_ent},
        runtime=True, timestamp=True, run=run,
    )

    sign_calls = {c[-1]: c for c in calls if c[0] == "codesign" and "--force" in c}

    # Downloader.xpc is explicitly mapped: it gets --entitlements, not
    # --preserve-metadata=entitlements.
    downloader_call = sign_calls[str(downloader_xpc)]
    assert "--entitlements" in downloader_call and str(downloader_ent) in downloader_call
    assert "--preserve-metadata=entitlements" not in downloader_call

    # Every other nested item (no explicit entitlements mapping) gets
    # --preserve-metadata=entitlements instead.
    autoupdate = framework / "Versions/B/Autoupdate"
    installer_xpc = framework / "Versions/B/XPCServices/Installer.xpc"
    for nested in (autoupdate, installer_xpc, framework):
        call = sign_calls[str(nested)]
        assert "--preserve-metadata=entitlements" in call

    # The top-level app keeps plain --entitlements semantics: with no
    # mapping given for it, it gets neither flag.
    app_call = sign_calls[str(app)]
    assert "--preserve-metadata=entitlements" not in app_call
    assert "--entitlements" not in app_call


def test_signing_order_skips_the_outer_bundles_own_main_executable(tmp_path):
    # Contents/MacOS/A is what signing A.app signs; a separate
    # preserve-metadata pass over it first would only leave a stale signature.
    app = _build_fake_sparkle_app(tmp_path)
    assert app / "Contents/MacOS/A" not in mr.signing_order(app)


_APP_ID = "com.apple.application-identifier"
_TEAM_ID = "com.apple.developer.team-identifier"


def _ents_runner(signed: dict[Path, dict], *, after_sign: dict[Path, dict] | None = None):
    """A run() whose `codesign -d --entitlements :- <p>` prints `signed[p]`
    (or `after_sign[p]` once any `codesign --force` has run) as an XML plist.
    Every other call succeeds silently and is recorded."""
    calls: list[list[str]] = []

    def run(argv: list[str]) -> subprocess.CompletedProcess:
        calls.append(argv)
        if argv[:4] == ["codesign", "-d", "--entitlements", ":-"]:
            path = Path(argv[-1])
            signed_yet = any(c[0] == "codesign" and "--force" in c for c in calls)
            table = after_sign if (signed_yet and after_sign is not None) else signed
            if path in table:
                return subprocess.CompletedProcess(argv, 0, plistlib.dumps(table[path]).decode(), "")
            return subprocess.CompletedProcess(argv, 0, "", "")
        return subprocess.CompletedProcess(argv, 0, "", "")

    return calls, run


def test_sign_bundle_refuses_preserved_application_identifier_without_profile(tmp_path):
    # Xcode's development signature on a profile-less helper carries
    # application-identifier; --preserve-metadata=entitlements would carry it
    # into the Developer ID signature and AMFI would kill the helper.
    app = _build_fake_sparkle_app(tmp_path)
    autoupdate = app / "Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
    calls, run = _ents_runner({autoupdate: {_APP_ID: "org.sparkle-project.Sparkle.Autoupdate"}})

    with pytest.raises(RuntimeError) as err:
        mr.sign_bundle(app, identity="X", entitlements={}, runtime=True, timestamp=False, run=run)

    message = str(err.value)
    assert "Sparkle.framework/Versions/B/Autoupdate" in message
    assert _APP_ID in message and "existing signature" in message
    # Refused while planning: nothing was signed.
    assert not any(c[0] == "codesign" and "--force" in c for c in calls)


def test_sign_bundle_refuses_mapped_file_claiming_team_identifier(tmp_path):
    app = _build_fake_sparkle_app(tmp_path)
    helper = app / "Contents/Helpers/cli"
    _write_macho(helper)
    ent = tmp_path / "cli.entitlements"
    ent.write_bytes(plistlib.dumps({_TEAM_ID: "T"}))
    _, run = _ents_runner({})

    with pytest.raises(RuntimeError, match=r"Contents/Helpers/cli.*cli\.entitlements.*team-identifier"):
        mr.sign_bundle(app, identity="X", entitlements={helper: ent},
                       runtime=True, timestamp=False, run=run)


def test_sign_bundle_mapped_empty_entitlements_replace_a_restricted_signature(tmp_path):
    # Mapping the helper to an entitlements file without the restricted keys
    # is the fix: the stale signature no longer matters.
    app = _build_fake_sparkle_app(tmp_path)
    autoupdate = app / "Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
    empty = tmp_path / "none.entitlements"
    empty.write_bytes(plistlib.dumps({}))
    calls, run = _ents_runner({autoupdate: {_APP_ID: "x"}}, after_sign={})

    mr.sign_bundle(app, identity="X", entitlements={autoupdate: empty},
                   runtime=True, timestamp=False, run=run)
    sign_calls = {c[-1]: c for c in calls if c[0] == "codesign" and "--force" in c}
    assert str(empty) in sign_calls[str(autoupdate)]


def test_sign_bundle_allows_restricted_entitlements_on_item_with_its_own_profile(tmp_path):
    app = _build_fake_sparkle_app(tmp_path)
    appex = app / "Contents/PlugIns/W.appex"
    _write_macho(appex / "Contents/MacOS/W")
    _write_plist(appex / "Contents/Info.plist", "W")
    (appex / "Contents/embedded.provisionprofile").write_bytes(b"profile")
    _, run = _ents_runner({appex: {_APP_ID: "T.w", _TEAM_ID: "T"}})

    mr.sign_bundle(app, identity="X", entitlements={}, runtime=True, timestamp=False, run=run)


def test_sign_bundle_rechecks_the_finished_signatures(tmp_path):
    # Clean before signing, but the signature codesign actually produced
    # carries application-identifier: the post-sign check must catch it.
    app = _build_fake_sparkle_app(tmp_path)
    installer = app / "Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices/Installer.xpc"
    _, run = _ents_runner({}, after_sign={installer: {_APP_ID: "x"}})

    with pytest.raises(RuntimeError, match="Installer.xpc"):
        mr.sign_bundle(app, identity="X", entitlements={}, runtime=True, timestamp=False, run=run)


def test_signed_entitlements_treats_unsigned_code_as_none(tmp_path):
    def run(argv):
        return subprocess.CompletedProcess(argv, 1, "", "code object is not signed at all")

    assert mr.signed_entitlements(tmp_path / "x", run=run) == {}


def test_sign_bundle_passes_runtime_timestamp_and_entitlements(tmp_path):
    app = tmp_path / "A.app"
    (app / "Contents/MacOS").mkdir(parents=True)
    ent = tmp_path / "a.entitlements"
    ent.write_text("<plist/>")
    calls, run = recorder()
    mr.sign_bundle(
        app, identity="Developer ID Application: X (T)", entitlements={app: ent},
        runtime=True, timestamp=True, run=run,
    )
    # signing_order(app) is just [app] here (no nested code), so sign_bundle
    # issues exactly one "codesign --force --sign ..." call followed by the
    # final "codesign --verify ..." call. Check the sign call specifically —
    # not calls[-1] — since the verify call correctly carries none of the
    # sign flags (runtime/timestamp/entitlements).
    assert len(calls) == 2
    sign_call, verify_call = calls
    assert sign_call[0] == "codesign" and "--options" in sign_call and "runtime" in sign_call
    assert "--timestamp" in sign_call and str(ent) in sign_call and sign_call[-1] == str(app)
    assert verify_call == ["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)]


def test_sign_bundle_raises_with_stderr_on_codesign_failure(tmp_path):
    app = tmp_path / "A.app"
    (app / "Contents/MacOS").mkdir(parents=True)

    def run(argv):
        return subprocess.CompletedProcess(argv, 1, "", "identity not found")

    with pytest.raises(RuntimeError, match="identity not found"):
        mr.sign_bundle(app, identity="X", entitlements={}, runtime=False, timestamp=False, run=run)


# ---------------------------------------------------------------------------
# notarize
# ---------------------------------------------------------------------------


def test_notarize_zips_app_submits_waits_and_staples(tmp_path):
    app = tmp_path / "A.app"
    app.mkdir()
    calls: list[list[str]] = []

    def run(argv):
        calls.append(argv)
        if argv[:3] == ["xcrun", "notarytool", "submit"]:
            return subprocess.CompletedProcess(argv, 0, json.dumps({"status": "Accepted", "id": "abc"}), "")
        return subprocess.CompletedProcess(argv, 0, "", "")

    mr.notarize(app, profile="p", run=run)

    assert calls[0][0] == "ditto" and "--keepParent" in calls[0]
    submit_call = next(c for c in calls if c[:3] == ["xcrun", "notarytool", "submit"])
    assert "--wait" in submit_call and "--keychain-profile" in submit_call and "p" in submit_call
    assert any(c[:3] == ["xcrun", "stapler", "staple"] for c in calls)
    assert any(c[:3] == ["xcrun", "stapler", "validate"] for c in calls)


def test_notarize_raises_with_log_when_not_accepted(tmp_path):
    app = tmp_path / "A.app"
    app.mkdir()

    def run(argv):
        if argv[:3] == ["xcrun", "notarytool", "submit"]:
            return subprocess.CompletedProcess(argv, 0, json.dumps({"status": "Invalid", "id": "abc"}), "")
        if argv[:3] == ["xcrun", "notarytool", "log"]:
            return subprocess.CompletedProcess(argv, 0, "log detail here", "")
        return subprocess.CompletedProcess(argv, 0, "", "")

    with pytest.raises(RuntimeError, match="log detail here"):
        mr.notarize(app, profile="p", run=run)


def test_notarize_cleans_up_temp_zip_directory(tmp_path):
    # Minor fix 6: notarize() must stage the .app zip in a TemporaryDirectory,
    # not a leaked mkdtemp() — assert the staging directory is gone afterward.
    app = tmp_path / "A.app"
    app.mkdir()
    seen: dict[str, object] = {}

    def run(argv):
        if argv[0] == "ditto":
            zip_path = Path(argv[-1])
            seen["zip_dir"] = zip_path.parent
            zip_path.write_bytes(b"")  # simulate ditto having created the zip
            return subprocess.CompletedProcess(argv, 0, "", "")
        if argv[:3] == ["xcrun", "notarytool", "submit"]:
            return subprocess.CompletedProcess(argv, 0, json.dumps({"status": "Accepted", "id": "abc"}), "")
        return subprocess.CompletedProcess(argv, 0, "", "")

    mr.notarize(app, profile="p", run=run)

    assert "zip_dir" in seen
    assert not seen["zip_dir"].exists()


# ---------------------------------------------------------------------------
# make_update_zip
# ---------------------------------------------------------------------------


def test_make_update_zip_uses_ditto_with_sequester_and_keep_parent(tmp_path):
    app = tmp_path / "A.app"
    app.mkdir()
    dest = tmp_path / "A.zip"
    calls, run = recorder()
    result = mr.make_update_zip(app, dest, run=run)
    assert result == dest
    assert calls[0] == ["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(app), str(dest)]


# ---------------------------------------------------------------------------
# render_distribution
# ---------------------------------------------------------------------------


def test_render_distribution_has_optional_choice_default_off_and_check():
    xml = mr.render_distribution(
        title="S", identifier="com.x", version="1.0", pkg_ref="S.pkg",
        optional_choices=[("acct", "Acct", "desc", "acct.pkg")],
        installation_check_js="return true;",
    )
    assert 'id="acct"' in xml and 'start_selected="false"' in xml
    assert "<installation-check" in xml and "return true;" in xml

    # the main pkg-ref carries both identifier and version, per fix round 1 minor 5
    assert '<pkg-ref id="com.x" version="1.0">S.pkg</pkg-ref>' in xml
    assert '<pkg-ref id="acct">acct.pkg</pkg-ref>' in xml

    # ...and the optional choice's <pkg-ref id="…"/> reference lives inside its own <choice>
    choice_block = xml.split('<choice id="acct"', 1)[1].split("</choice>", 1)[0]
    assert '<pkg-ref id="acct"/>' in choice_block


def test_render_distribution_escapes_text_and_omits_check_when_absent():
    xml = mr.render_distribution(
        title='S & "Co"', identifier="com.x", version="1.0", pkg_ref="S.pkg",
        optional_choices=[], installation_check_js=None,
    )
    assert "<installation-check" not in xml
    assert "S & \"Co\"" not in xml
    assert "&amp;" in xml and "&quot;" in xml


def test_render_distribution_wraps_check_js_in_cdata_and_parses(tmp_path):
    xml = mr.render_distribution(
        title="S", identifier="com.x", version="1.0", pkg_ref="S.pkg",
        optional_choices=[], installation_check_js='if (a < b && c > 1) { return true; }',
    )
    assert "<![CDATA[" in xml and "]]>" in xml
    # The CDATA section must actually contain the raw, unescaped JS.
    assert 'if (a < b && c > 1) { return true; }' in xml
    # And the whole document must still be well-formed XML once CDATA-wrapped.
    ET.fromstring(xml)


def test_render_distribution_raises_when_check_js_contains_cdata_terminator():
    with pytest.raises(ValueError, match=r"\]\]>"):
        mr.render_distribution(
            title="S", identifier="com.x", version="1.0", pkg_ref="S.pkg",
            optional_choices=[], installation_check_js="var x = ']]>';",
        )


def test_render_distribution_allow_external_scripts_emits_attribute():
    xml_default = mr.render_distribution(
        title="S", identifier="com.x", version="1.0", pkg_ref="S.pkg",
        optional_choices=[], installation_check_js=None,
    )
    assert "allow-external-scripts" not in xml_default

    xml_allowed = mr.render_distribution(
        title="S", identifier="com.x", version="1.0", pkg_ref="S.pkg",
        optional_choices=[], installation_check_js=None, allow_external_scripts=True,
    )
    assert 'allow-external-scripts="yes"' in xml_allowed


# ---------------------------------------------------------------------------
# build_pkg
# ---------------------------------------------------------------------------


def test_build_pkg_writes_distribution_and_copies_extra_packages(tmp_path):
    app = tmp_path / "A.app"
    app.mkdir()
    scripts = tmp_path / "scripts"
    scripts.mkdir()
    extra = tmp_path / "acct.pkg"
    extra.write_text("extra-pkg-bytes")
    dest = tmp_path / "out" / "A.pkg"
    dest.parent.mkdir()
    distribution_xml = "<installer-gui-script/>"
    seen: dict[str, object] = {}

    def run(argv):
        if argv[0] == "pkgbuild" and "--analyze" in argv:
            with Path(argv[-1]).open("wb") as f:
                plistlib.dump([{"RootRelativeBundlePath": "A.app", "BundleIsRelocatable": True}], f)
            return subprocess.CompletedProcess(argv, 0, "", "")
        if argv[0] == "pkgbuild":
            assert "--component-plist" in argv
            assert "--install-location" in argv and "/Applications" in argv
            assert "--identifier" in argv and "com.x" in argv
            assert "--version" in argv and "1.0" in argv
            assert "--scripts" in argv and str(scripts) in argv
            return subprocess.CompletedProcess(argv, 0, "", "")
        if argv[0] == "productbuild":
            package_path = Path(argv[argv.index("--package-path") + 1])
            seen["package_path_has_extra"] = (package_path / "acct.pkg").exists()
            seen["distribution_contents"] = Path(argv[argv.index("--distribution") + 1]).read_text()
            seen["has_sign"] = "--sign" in argv
            return subprocess.CompletedProcess(argv, 0, "", "")
        return subprocess.CompletedProcess(argv, 0, "", "")

    result = mr.build_pkg(
        app, identifier="com.x", version="1.0", scripts=scripts, distribution=distribution_xml,
        identity="Developer ID Installer: X (T)", dest=dest, run=run, extra_packages=[extra],
    )
    assert result == dest
    assert seen["package_path_has_extra"] is True
    assert seen["distribution_contents"] == distribution_xml
    assert seen["has_sign"] is True


def test_build_pkg_stages_app_via_ditto_before_analyzing(tmp_path):
    # Fix round 1, Important 3: the app must be staged into a temp root via
    # `ditto` (keeping symlinks) before pkgbuild ever sees it, so the
    # resulting component is built from that root, never from `app` directly.
    app = tmp_path / "A.app"
    app.mkdir()
    scripts = tmp_path / "scripts"
    scripts.mkdir()
    dest = tmp_path / "A.pkg"
    seen: dict[str, object] = {}

    def run(argv):
        if argv[0] == "ditto":
            seen["ditto_call"] = argv
            assert argv[1] == str(app)
            return subprocess.CompletedProcess(argv, 0, "", "")
        if argv[0] == "pkgbuild" and "--analyze" in argv:
            seen["analyze_root"] = argv[argv.index("--root") + 1]
            with Path(argv[-1]).open("wb") as f:
                plistlib.dump([{"RootRelativeBundlePath": "A.app", "BundleIsRelocatable": True}], f)
            return subprocess.CompletedProcess(argv, 0, "", "")
        if argv[0] == "pkgbuild":
            seen["component_root"] = argv[argv.index("--root") + 1]
            return subprocess.CompletedProcess(argv, 0, "", "")
        return subprocess.CompletedProcess(argv, 0, "", "")

    mr.build_pkg(
        app, identifier="com.x", version="1.0", scripts=scripts, distribution="<x/>",
        identity=None, dest=dest, run=run,
    )

    assert "ditto_call" in seen
    staged_app = Path(seen["ditto_call"][2])
    assert staged_app != app
    assert staged_app.name == app.name
    # analyze and the final component build must both run against the same staged root
    assert seen["analyze_root"] == seen["component_root"] == str(staged_app.parent)


def test_build_pkg_forces_bundle_non_relocatable_via_component_plist(tmp_path):
    # Fix round 1, Important 3: every entry pkgbuild --analyze wrote must be
    # flipped to BundleIsRelocatable=False before the final --component-plist
    # build, and the final pkgbuild argv must actually use --component-plist.
    app = tmp_path / "A.app"
    app.mkdir()
    scripts = tmp_path / "scripts"
    scripts.mkdir()
    dest = tmp_path / "A.pkg"
    seen: dict[str, object] = {}

    def run(argv):
        if argv[0] == "pkgbuild" and "--analyze" in argv:
            plist_path = Path(argv[-1])
            with plist_path.open("wb") as f:
                plistlib.dump(
                    [{"RootRelativeBundlePath": "A.app", "BundleIsRelocatable": True}], f
                )
            return subprocess.CompletedProcess(argv, 0, "", "")
        if argv[0] == "pkgbuild":
            seen["component_call"] = argv
            plist_path = Path(argv[argv.index("--component-plist") + 1])
            with plist_path.open("rb") as f:
                seen["component_plist_entries"] = plistlib.load(f)
            return subprocess.CompletedProcess(argv, 0, "", "")
        return subprocess.CompletedProcess(argv, 0, "", "")

    mr.build_pkg(
        app, identifier="com.x", version="1.0", scripts=scripts, distribution="<x/>",
        identity=None, dest=dest, run=run,
    )

    assert "--component-plist" in seen["component_call"]
    entries = seen["component_plist_entries"]
    assert entries and all(entry["BundleIsRelocatable"] is False for entry in entries)


def test_build_pkg_raises_when_extra_package_collides_with_component_pkg(tmp_path):
    # Fix round 1, Important 2: an extra_packages entry named the same as the
    # reserved COMPONENT_PKG filename must raise, never silently overwrite it.
    app = tmp_path / "A.app"
    app.mkdir()
    scripts = tmp_path / "scripts"
    scripts.mkdir()
    dest = tmp_path / "A.pkg"
    colliding = tmp_path / mr.COMPONENT_PKG
    colliding.write_text("not the real component")
    calls, run = recorder()

    with pytest.raises(ValueError, match="component.pkg"):
        mr.build_pkg(
            app, identifier="com.x", version="1.0", scripts=scripts, distribution="<x/>",
            identity=None, dest=dest, run=run, extra_packages=[colliding],
        )


def test_build_pkg_omits_sign_flag_when_no_identity(tmp_path):
    app = tmp_path / "A.app"
    app.mkdir()
    scripts = tmp_path / "scripts"
    scripts.mkdir()
    dest = tmp_path / "A.pkg"
    calls, run = recorder()
    mr.build_pkg(
        app, identifier="com.x", version="1.0", scripts=scripts, distribution="<x/>",
        identity=None, dest=dest, run=run,
    )
    product_call = calls[-1]
    assert "--sign" not in product_call
    assert product_call[-1] == str(dest)


def test_build_pkg_raises_with_stderr_on_pkgbuild_failure(tmp_path):
    app = tmp_path / "A.app"
    app.mkdir()
    scripts = tmp_path / "scripts"
    scripts.mkdir()
    dest = tmp_path / "A.pkg"

    def run(argv):
        if argv[0] == "pkgbuild" and "--analyze" in argv:
            with Path(argv[-1]).open("wb") as f:
                plistlib.dump([{"RootRelativeBundlePath": "A.app", "BundleIsRelocatable": True}], f)
            return subprocess.CompletedProcess(argv, 0, "", "")
        if argv[0] == "pkgbuild":
            return subprocess.CompletedProcess(argv, 1, "", "bad component")
        return subprocess.CompletedProcess(argv, 0, "", "")

    with pytest.raises(RuntimeError, match="bad component"):
        mr.build_pkg(
            app, identifier="com.x", version="1.0", scripts=scripts, distribution="<x/>",
            identity=None, dest=dest, run=run,
        )


# ---------------------------------------------------------------------------
# asset_for
# ---------------------------------------------------------------------------


def test_asset_for_computes_size_and_sha256(tmp_path):
    f = tmp_path / "x.bin"
    f.write_bytes(b"hello world")
    asset = mr.asset_for(f, "https://example.com/x.bin")
    assert asset.url == "https://example.com/x.bin"
    assert asset.size == 11
    assert asset.sha256 == hashlib.sha256(b"hello world").hexdigest()


# ---------------------------------------------------------------------------
# publish_github_release
# ---------------------------------------------------------------------------


def test_publish_github_release_invokes_gh_release_create(tmp_path):
    notes = tmp_path / "notes.md"
    notes.write_text("n")
    asset1 = tmp_path / "A.pkg"
    asset1.write_text("p")
    calls, run = recorder()
    mr.publish_github_release(
        repo="me/repo", tag="v1.0", title="v1.0", notes_file=notes, assets=[asset1], run=run,
    )
    call = calls[0]
    assert call[:3] == ["gh", "release", "create"] and "v1.0" in call
    assert str(asset1) in call and "--repo" in call and "me/repo" in call
    assert "--notes-file" in call and str(notes) in call


def test_publish_github_release_raises_with_stderr_on_gh_failure(tmp_path):
    notes = tmp_path / "notes.md"
    notes.write_text("n")

    def run(argv):
        return subprocess.CompletedProcess(argv, 1, "", "release already exists")

    with pytest.raises(RuntimeError, match="release already exists"):
        mr.publish_github_release(
            repo="me/repo", tag="v1.0", title="v1.0", notes_file=notes, assets=[], run=run,
        )
