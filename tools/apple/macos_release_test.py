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
import subprocess
from pathlib import Path

import pytest

import macos_release as mr


def recorder():
    calls: list[list[str]] = []

    def run(argv: list[str]) -> subprocess.CompletedProcess:
        calls.append(argv)
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

    # each pkg-ref has a top-level <pkg-ref id=…>file</pkg-ref> entry
    assert '<pkg-ref id="default">S.pkg</pkg-ref>' in xml
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
        if argv[0] == "pkgbuild":
            assert "--component" in argv and str(app) in argv
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
