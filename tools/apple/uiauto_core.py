"""Drive a scriptable macOS app described by an `AppProfile` without taking the user's focus.

Every window this opens is a real, laid-out, rendered AppKit window — it is
simply sunk behind the desktop picture, so screenshots and hit-testing work
while the person at the keyboard never sees it and never loses focus. One
debug-only switch makes that possible, passed at launch:

    -QuietWindowPresentation YES   every window presents sunk, nothing activates

It is read through the `NSArgumentDomain`, so a copy launched any other way is
unaffected. Unlike Stenographer there is no `-MultipleInstances` switch: this
app is not an `LSUIElement` singleton, so `open -n` already starts a second copy
beside an installed one.

Five design decisions here are not preferences; each one exists because the
obvious version broke something:

*   **Address the app by full bundle path, never by name.** `tell application
    "Agentic Developer Hub"` resolves through LaunchServices by bundle id and
    picks *one of* the running copies — exactly wrong when a worktree is driving
    its own build beside an installed one. `tell application "/full/path.app"`
    reaches that copy deterministically. Both `ui state` and `window list` reply
    with `pid` and a bundle path so a caller can prove which copy answered.

*   **Find instances by executable path, not process name.** `pkill -x` would
    kill the user's installed copy and every other worktree's copy along with
    this one. `parse_ps` matches on the path under the bundle.

*   **Wait for an Apple-event answer, not for a pid.** A pid exists long before
    the scripting bridge is up, and a caller that races that gets a timeout
    instead of an answer.

*   **Keyboard input goes through `CGEventPostToPid`, not System Events.**
    System Events' `keystroke` goes to whatever is frontmost, so using it means
    foregrounding the app — the one thing this harness exists to avoid.

*   **Screenshot by window number from the app's own `window list`.** A sunk
    window is invisible to `CGWindowListCopyWindowInfo` with
    `kCGWindowListExcludeDesktopElements` — the flag every convenience wrapper
    passes — so a tool that looks the window up that way reports a driven app as
    having no windows at all.

    scripts/uiauto.py build
    scripts/uiauto.py launch
    scripts/uiauto.py wait phase signIn --timeout 30
    scripts/uiauto.py state
    scripts/uiauto.py axids
    scripts/uiauto.py shot main
    scripts/uiauto.py quit
"""

from __future__ import annotations

import argparse
import ctypes
import json
import os
import plistlib
import shutil
import signal
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Any, Callable

EMBED_SCRIPT = Path(__file__).resolve().parent / "embed_transitive_frameworks.py"


@dataclass(frozen=True)
class AppProfile:
    prog: str                       # argparse prog, e.g. "uiauto.py"
    description: str                # module docstring of the host script
    derived_data: Path
    default_app: Path
    workspace: Path
    scheme: str
    quiet_args: list[str]
    window_titles: dict[str, str]   # script name -> window title
    screenshot_prefix: str          # "/tmp/<prefix>-<name>.png" default for `shot`
    commands_no_arg: dict[str, str]
    commands_with_arg: dict[str, str]
    quits_the_app: set[tuple[str, str]]
    configure_parser: Callable[[argparse._SubParsersAction], None] = lambda sub: None
    handle: Callable[[argparse.Namespace, Path], int | None] = lambda args, app: None


# --------------------------------------------------------------------------
# AppleScript plumbing
# --------------------------------------------------------------------------

def applescript_quote(value: str) -> str:
    """Quote a Python string as an AppleScript string literal."""
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def tell_script(app: Path, command: str) -> str:
    """An AppleScript that addresses one exact copy of the app by its path."""
    return f"tell application {applescript_quote(str(app))} to {command}"


def osascript(app: Path, command: str, timeout: float = 60.0) -> str:
    """Run one command against the app, returning its reply text.

    Raises RuntimeError carrying osascript's own stderr, which is the only
    place an Apple-event failure says anything useful.
    """
    proc = subprocess.run(
        ["osascript", "-e", tell_script(app, command)],
        capture_output=True, text=True, timeout=timeout,
    )
    if proc.returncode != 0:
        raise RuntimeError(
            f"osascript failed ({proc.returncode}) for {command!r}: "
            f"{proc.stderr.strip()}"
        )
    return proc.stdout.rstrip("\n")


# --------------------------------------------------------------------------
# Instance discovery — by executable path, never by process name
# --------------------------------------------------------------------------

def parse_ps(output: str, executable_prefix: str) -> list[int]:
    """Pids from `ps -Ao pid=,comm=` output whose binary is under a prefix.

    Matching on the path, not the name, is the whole point: `pkill -x` on this
    app's name kills the user's installed copy and every other worktree's copy
    along with this one.
    """
    pids: list[int] = []
    for line in output.splitlines():
        line = line.strip()
        if not line:
            continue
        pid_text, _, command = line.partition(" ")
        if command.strip().startswith(executable_prefix):
            try:
                pids.append(int(pid_text))
            except ValueError:
                continue
    return pids


def executable_prefixes(app: Path) -> list[str]:
    """Every spelling of this bundle's executable directory `ps` might report.

    Both spellings, because this project's DerivedData directory is a symlink
    onto an external volume: a caller names the bundle through
    `~/Library/Developer/Xcode/DerivedData/...`, and `ps` reports the resolved
    `/Volumes/Xcode-artifacts/...` the kernel actually exec'd. Matching only the
    caller's spelling finds no process at all — the app looks like it never
    started when it is running perfectly well.
    """
    prefixes: list[str] = []
    for candidate in (app, Path(os.path.realpath(app))):
        prefix = str(candidate / "Contents" / "MacOS") + "/"
        if prefix not in prefixes:
            prefixes.append(prefix)
    return prefixes


def running_pids(app: Path) -> list[int]:
    """Pids of copies running out of this exact bundle."""
    output = subprocess.run(
        ["ps", "-Ao", "pid=,comm="], capture_output=True, text=True,
    ).stdout
    pids: list[int] = []
    for prefix in executable_prefixes(app):
        for pid in parse_ps(output, prefix):
            if pid not in pids:
                pids.append(pid)
    return sorted(pids)


def bundle_version(app: Path) -> str:
    """`CFBundleShortVersionString` of a built bundle, or '?' if unreadable."""
    try:
        with open(app / "Contents" / "Info.plist", "rb") as handle:
            return plistlib.load(handle).get("CFBundleShortVersionString", "?")
    except (OSError, plistlib.InvalidFileException):
        return "?"


def frontmost_app() -> str:
    """Name of the frontmost application, for proving focus was not stolen."""
    proc = subprocess.run(
        ["osascript", "-e",
         'tell application "System Events" to get name of first '
         "application process whose frontmost is true"],
        capture_output=True, text=True,
    )
    return proc.stdout.strip()


# --------------------------------------------------------------------------
# Launch / quit / build
# --------------------------------------------------------------------------

def launch_argv(profile: AppProfile, app: Path) -> list[str]:
    """The `open` command line that starts a new quiet, parallel instance.

    `-n` is a new instance even though one is running; `-g` keeps the launch
    from activating the app. Both are needed: `-g` alone hands an already
    running copy the event instead of starting ours.
    """
    return ["open", "-n", "-g", "-a", str(app), "--args", *profile.quiet_args]


def launch_instance(profile: AppProfile, app: Path, wait: float = 60.0) -> int:
    """Start a quiet instance of this bundle and return the pid that answers.

    Waits for the app to answer an Apple event rather than for a process to
    appear — a pid exists long before the scripting bridge is up, and a caller
    that races that gets a timeout instead of an answer.
    """
    before = set(running_pids(app))
    subprocess.run(launch_argv(profile, app), check=True)

    deadline = time.monotonic() + wait
    while time.monotonic() < deadline:
        if any(pid not in before for pid in running_pids(app)):
            try:
                reply = json.loads(osascript(app, "window list", timeout=10))
            except (RuntimeError, subprocess.TimeoutExpired, json.JSONDecodeError):
                time.sleep(0.25)
                continue
            return int(reply["pid"])
        time.sleep(0.25)
    raise RuntimeError(f"{app} did not come up within {wait}s")


def quit_instances(app: Path, wait: float = 10.0) -> list[int]:
    """Terminate every copy running out of this bundle. Returns the pids."""
    pids = running_pids(app)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.monotonic() + wait
    while time.monotonic() < deadline and running_pids(app):
        time.sleep(0.25)
    for pid in running_pids(app):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    return pids


def build_app(profile: AppProfile, app: Path) -> None:
    """Build the app into the project's shared DerivedData.

    No `clean`, ever, and never a second derived-data tree: that directory is a
    symlink onto a slow external volume, where a clean costs a quarter of an
    hour of link time for nothing. Two `xcodebuild` runs against it at once race
    and the loser silently drives the other's binary, so callers must not run
    this concurrently with another build.
    """
    subprocess.run(
        ["xcodebuild", "-workspace", str(profile.workspace), "-scheme", profile.scheme,
         "-destination", "platform=macOS",
         "-derivedDataPath", str(profile.derived_data), "build"],
        check=True,
    )
    embed_transitive_frameworks(app)


def embed_transitive_frameworks(app: Path) -> None:
    """Copy the frameworks Xcode leaves behind into the built bundle.

    Xcode embeds a target's *direct* framework dependencies and no others, so a
    framework reached only through another framework is linked but never copied.
    The app's own `Contents/Frameworks` rpath then has a hole in it and dyld
    kills the process at launch — `Library not loaded:
    @rpath/AgenticToolkitCore.framework/...`, referenced from the embedded
    `AgenticToolkitCoreMacOS`, which is exactly what a Debug build of this app
    did before this call existed.

    `install` already runs this helper over its Release build for the same
    reason; a Debug build launched out of DerivedData needs it just as much, and
    the driver is the only thing that launches one. Idempotent, and cheap
    compared to the build it follows.
    """
    products = app.parent
    subprocess.run(
        [sys.executable, str(EMBED_SCRIPT), str(app), str(products)],
        check=True,
    )


# --------------------------------------------------------------------------
# Screenshots
# --------------------------------------------------------------------------

def window_number(profile: AppProfile, app: Path, name: str) -> int:
    """The CoreGraphics window number of a named window.

    Matched against the window list the app itself reports, because a sunk
    window is invisible to `CGWindowListCopyWindowInfo` with
    `kCGWindowListExcludeDesktopElements` — the flag every convenience wrapper
    passes — and a screenshot tool that looks the window up that way reports a
    driven app as having no windows at all.
    """
    inventory = json.loads(osascript(app, "window list"))
    wanted = profile.window_titles.get(name.lower(), name).lower()
    for window in inventory["windows"]:
        if window["class"] == "NSStatusBarWindow":
            continue
        if wanted in window["title"].lower():
            return int(window["number"])
    titles = [w["title"] for w in inventory["windows"]]
    raise RuntimeError(f"no window matching {name!r}; open windows: {titles}")


def screenshot(profile: AppProfile, app: Path, name: str, destination: Path) -> Path:
    """Capture one window by number — sunk or not, focused or not.

    `screencapture -l` is the first choice because it is the app-independent
    one, but it is gated on the *caller's* Screen Recording grant, and a caller
    without one gets a silent zero-byte file rather than an error. The app's own
    `screenshot window` command captures the same window from inside the
    process, which needs no grant at all, so it is the fallback: the point of
    this function is a PNG of that window, not a particular way of taking it.
    """
    number = window_number(profile, app, name)
    destination.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["screencapture", "-x", "-o", "-l", str(number), str(destination)],
        check=True,
    )
    if destination.exists() and destination.stat().st_size > 0:
        return destination

    inside = osascript(app, f"screenshot window {applescript_quote(name)}")
    if not inside:
        raise RuntimeError(
            f"neither screencapture nor the app could capture {name!r}"
        )
    shutil.copyfile(inside, destination)
    return destination


# --------------------------------------------------------------------------
# Waiting on asynchronous state
# --------------------------------------------------------------------------

def json_path(data: Any, path: str) -> Any:
    """Follow a dotted path through parsed JSON, `None` where it does not lead.

    Numeric components index arrays, so `htdv.levels.0.selectedItemID` reads the
    root rail's selection. `None` rather than an exception for a missing path:
    `wait` polls a state that legitimately does not have the key yet.
    """
    current = data
    for part in path.split("."):
        if isinstance(current, list):
            try:
                current = current[int(part)]
            except (ValueError, IndexError):
                return None
        elif isinstance(current, dict):
            if part not in current:
                return None
            current = current[part]
        else:
            return None
    return current


def as_text(value: Any) -> str:
    """A JSON value as the text `wait` compares against, so `true` matches."""
    if isinstance(value, str):
        return value
    return json.dumps(value)


def wait_for(app: Path, path: str, expected: str, timeout: float,
             interval: float = 0.25) -> tuple[bool, str]:
    """Poll `ui state` until a JSON path equals a value, or time runs out.

    Every scripted action in this app is asynchronous — the sdef commands answer
    `true` meaning *accepted*, not *done* — so without this every caller
    hand-rolls a sleep loop and gets it wrong. Returns whether it matched and
    the last state text seen, so a timeout can print what the app was actually
    showing instead of only that it was not what was asked for.
    """
    deadline = time.monotonic() + timeout
    last = "{}"
    while True:
        try:
            last = osascript(app, "ui state", timeout=20)
            if as_text(json_path(json.loads(last), path)) == expected:
                return True, last
        except (RuntimeError, subprocess.TimeoutExpired, json.JSONDecodeError):
            pass
        if time.monotonic() >= deadline:
            return False, last
        time.sleep(interval)


# --------------------------------------------------------------------------
# Keyboard input, delivered to a background process
# --------------------------------------------------------------------------

# System Events' `keystroke` goes to whatever is frontmost, so using it means
# foregrounding the app — the one thing this whole harness exists to avoid.
# `CGEventPostToPid` addresses a process directly and needs no activation.
_APPLICATION_SERVICES = (
    "/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices"
)

KEY_CODES = {
    "return": 36, "enter": 36, "tab": 48, "space": 49, "delete": 51,
    "escape": 53, "esc": 53, "left": 123, "right": 124, "down": 125, "up": 126,
}


def _core_graphics() -> ctypes.CDLL:
    lib = ctypes.cdll.LoadLibrary(_APPLICATION_SERVICES)
    lib.CGEventCreateKeyboardEvent.restype = ctypes.c_void_p
    lib.CGEventCreateKeyboardEvent.argtypes = [
        ctypes.c_void_p, ctypes.c_uint16, ctypes.c_bool,
    ]
    lib.CGEventKeyboardSetUnicodeString.restype = None
    lib.CGEventKeyboardSetUnicodeString.argtypes = [
        ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(ctypes.c_uint16),
    ]
    lib.CGEventPostToPid.restype = None
    lib.CGEventPostToPid.argtypes = [ctypes.c_int, ctypes.c_void_p]
    lib.CFRelease.restype = None
    lib.CFRelease.argtypes = [ctypes.c_void_p]
    return lib


def _post(lib: ctypes.CDLL, pid: int, code: int, text: str | None) -> None:
    for down in (True, False):
        event = lib.CGEventCreateKeyboardEvent(None, code, down)
        if text is not None:
            units = text.encode("utf-16-le")
            count = len(units) // 2
            buffer = (ctypes.c_uint16 * count).from_buffer_copy(units)
            lib.CGEventKeyboardSetUnicodeString(event, count, buffer)
        lib.CGEventPostToPid(pid, event)
        lib.CFRelease(event)
        time.sleep(0.01)


def press_keys(pid: int, keys: list[str]) -> None:
    """Send named keys (return, tab, escape, arrows…) to one process."""
    lib = _core_graphics()
    for key in keys:
        code = KEY_CODES.get(key.lower())
        if code is None:
            raise RuntimeError(
                f"unknown key {key!r}; known: {', '.join(sorted(KEY_CODES))}"
            )
        _post(lib, pid, code, None)


def type_text(pid: int, text: str) -> None:
    """Type literal text into one process, one character at a time.

    Keycode 0 with a unicode string attached types the character whatever the
    layout is, so this does not depend on the user's keyboard layout.
    """
    lib = _core_graphics()
    for character in text:
        _post(lib, pid, 0, character)


# --------------------------------------------------------------------------
# Command line
# --------------------------------------------------------------------------

def build_parser(profile: AppProfile) -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog=profile.prog, description=profile.description,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--app", type=Path, default=profile.default_app,
        help=f"app bundle to drive (default: {profile.default_app})",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("build", help="build the app into the project's DerivedData")
    sub.add_parser("launch", help="start a quiet instance and print its pid")
    sub.add_parser("quit", help="terminate copies running out of this bundle")
    sub.add_parser("pids", help="list pids running out of this bundle")

    for name, command in sorted(profile.commands_no_arg.items()):
        sub.add_parser(name, help=command)

    for name, command in sorted(profile.commands_with_arg.items()):
        child = sub.add_parser(name, help=command.format(arg="…"))
        child.add_argument("argument")

    shot = sub.add_parser("shot", help="screenshot a window by name, sunk or not")
    shot.add_argument("name", help="a window name, or a title substring")
    shot.add_argument("--out", type=Path, default=None, help="PNG path to write")

    waiter = sub.add_parser(
        "wait", help="poll `ui state` until a JSON path equals a value")
    waiter.add_argument("path", help="dotted path, e.g. phase or htdv.levels.0.title")
    waiter.add_argument("expected", help="value to wait for, e.g. ready")
    waiter.add_argument("--timeout", type=float, default=30.0)
    waiter.add_argument("--interval", type=float, default=0.25)

    press = sub.add_parser("press", help="send named keys to the running instance")
    press.add_argument("keys", nargs="+",
                       help=f"one of: {', '.join(sorted(KEY_CODES))}")

    typer = sub.add_parser("type", help="type literal text into the running instance")
    typer.add_argument("text")

    profile.configure_parser(sub)

    return parser


def target_pid(app: Path) -> int:
    pids = running_pids(app)
    if not pids:
        raise RuntimeError(f"no instance of {app} is running — run `launch` first")
    return pids[-1]


def main(profile: AppProfile, argv: list[str] | None = None) -> int:
    args = build_parser(profile).parse_args(argv)
    app: Path = args.app
    command: str = args.command

    result = profile.handle(args, app)
    if result is not None:
        return result

    if command == "build":
        build_app(profile, app)
        print(f"built {app} ({bundle_version(app)})")
        return 0

    if not app.exists():
        print(f"no app bundle at {app} — run `uiauto.py build`", file=sys.stderr)
        return 2

    if command == "launch":
        before = frontmost_app()
        pid = launch_instance(profile, app)
        print(json.dumps({
            "app": str(app),
            "version": bundle_version(app),
            "pid": pid,
            "frontmost_before": before,
            "frontmost_after": frontmost_app(),
        }, indent=2))
        return 0

    if command == "quit":
        print(json.dumps({"app": str(app), "terminated": quit_instances(app)}))
        return 0

    if command == "pids":
        print(json.dumps({"app": str(app), "pids": running_pids(app)}))
        return 0

    if command == "shot":
        out = args.out or Path(f"/tmp/{profile.screenshot_prefix}-{args.name}.png")
        print(screenshot(profile, app, args.name, out))
        return 0

    if command == "wait":
        matched, state = wait_for(app, args.path, args.expected,
                                  args.timeout, args.interval)
        print(state)
        if not matched:
            print(
                f"timed out after {args.timeout}s waiting for "
                f"{args.path} == {args.expected!r}",
                file=sys.stderr,
            )
            return 1
        return 0

    if command == "press":
        press_keys(target_pid(app), args.keys)
        return 0

    if command == "type":
        type_text(target_pid(app), args.text)
        return 0

    if command in profile.commands_no_arg:
        print(osascript(app, profile.commands_no_arg[command]))
        return 0

    template = profile.commands_with_arg[command]
    if (command, args.argument.strip().lower()) in profile.quits_the_app:
        pids = running_pids(app)
        try:
            print(osascript(app, template.format(
                arg=applescript_quote(args.argument)), timeout=20))
        except (RuntimeError, subprocess.TimeoutExpired):
            pass
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline and running_pids(app):
            time.sleep(0.25)
        print(json.dumps({"quit_the_app": True, "was_running": pids,
                          "still_running": running_pids(app)}))
        return 0
    print(osascript(app, template.format(arg=applescript_quote(args.argument))))
    return 0
