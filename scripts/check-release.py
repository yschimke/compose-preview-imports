#!/usr/bin/env python3
"""Check that the release PR's version sources agree before it can merge."""
import json
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
version = (root / "version.txt").read_text().strip()
assert re.fullmatch(r"[0-9]+\.[0-9]+\.[0-9]+", version), f"invalid release version: {version}"
manifest = json.loads((root / ".release-please-manifest.json").read_text())
assert manifest == {".": version}, "release manifest and version.txt disagree"
config = json.loads((root / "release-please-config.json").read_text())
assert config["release-type"] == "simple"
assert config["versioning"] == "always-bump-minor"
assert set(config["packages"]) == {"."}
print("Release metadata agrees")
