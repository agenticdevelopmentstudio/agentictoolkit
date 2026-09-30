#!/usr/bin/env python3
"""Post-build phase for every .aiplugin target: mirror the built bundle into
~/.agenticplugins so a ⌘R or ./install picks up the fresh plugin.

A packaging build (Stenographer's scripts/release.py) sets the build setting
AGENTIC_SKIP_PLUGIN_SELF_INSTALL=YES: it bundles the plugins into the app it
ships, and must never overwrite the plugins the developer's own installed app
is running.
"""
from __future__ import annotations

import os
import subprocess
import sys
from pathlib import Path


def main() -> int:
    env = os.environ
    if env.get("AGENTIC_SKIP_PLUGIN_SELF_INSTALL") == "YES":
        print(f"skipping ~/.agenticplugins install of {env.get('FULL_PRODUCT_NAME')} "
              "(AGENTIC_SKIP_PLUGIN_SELF_INSTALL=YES)")
        return 0
    product = env["FULL_PRODUCT_NAME"]
    source = Path(env["BUILT_PRODUCTS_DIR"]) / product
    dest = Path.home() / ".agenticplugins" / product
    dest.parent.mkdir(parents=True, exist_ok=True)
    return subprocess.run(
        ["/usr/bin/rsync", "-a", "--delete", f"{source}/", f"{dest}/"]).returncode


if __name__ == "__main__":
    sys.exit(main())
