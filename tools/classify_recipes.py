#!/usr/bin/env python3
"""Sort the recipes into what moves, what stays, and what needs a human.

Three buckets, because two is what a hand-written list gets wrong. A recipe can
name a package that stayed behind, OR name one of the twelve modules carved out
into adh-ui — and the second kind reads as perfectly generic right up until you
publish it and a reader follows the import.
"""
import argparse
import json
import re
import sys
from pathlib import Path

MOVED = {"ui", "landing", "markdown", "search", "editing", "controls", "model", "themes"}

# The carve-out, by module name and by exported symbol: a recipe can cite either.
CARVE_OUT = (
    "rdid", "invitations-endpoints", "invitations-types", "help-ids", "rdid-editor",
    "rdid-picker", "invitation-panes", "send-invitation-modal", "admin-notes-modal",
    "notes-and-history", "transfer-ownership-section", "delete-entity-section",
    "RdidPicker", "RdidEditor", "SendInvitationModal", "AdminNotesModal",
    "NotesAndHistory", "TransferOwnershipSection", "DeleteEntitySection", "InvitationPanes",
)

SCOPE_RE = re.compile(r"@agentic-toolkit/([a-z0-9-]+)")


def classify(path: Path) -> tuple[str, list[str]]:
    text = path.read_text(encoding="utf-8")
    carve_hits = sorted({c for c in CARVE_OUT if c in text})
    unmoved = sorted(set(SCOPE_RE.findall(text)) - MOVED)
    if carve_hits:
        return "carve-out", carve_hits + [f"@agentic-toolkit/{u}" for u in unmoved]
    if unmoved:
        return "unmoved", [f"@agentic-toolkit/{u}" for u in unmoved]
    return "clean", []


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root", type=Path, default=Path(__file__).resolve().parents[1] / "cookbook"
    )
    parser.add_argument("--bucket", choices=("clean", "unmoved", "carve-out"))
    args = parser.parse_args()

    files = sorted(args.root.rglob("*.md"))
    if not files:
        # An empty scan is a broken path, never a pass.
        print(f"classify_recipes: no recipes under {args.root}", file=sys.stderr)
        return 2

    buckets: dict[str, dict[str, list[str]]] = {"clean": {}, "unmoved": {}, "carve-out": {}}
    for path in files:
        bucket, why = classify(path)
        buckets[bucket][path.name] = why

    if args.bucket:
        for name in buckets[args.bucket]:
            print(name)
        return 0

    print(json.dumps(buckets, indent=2))
    print(
        f"\n{len(files)} recipes: {len(buckets['clean'])} clean, "
        f"{len(buckets['unmoved'])} name an unmoved package, "
        f"{len(buckets['carve-out'])} cite the carve-out",
        file=sys.stderr,
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
