#!/usr/bin/env python3
import plistlib
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
INFO_PLIST = ROOT / "apps/macos/Resources/Info.plist"


with INFO_PLIST.open("rb") as file:
    info = plistlib.load(file)

version = str(info["CFBundleShortVersionString"])
build = str(info["CFBundleVersion"])
if not re.fullmatch(r"\d+\.\d+\.\d+", version):
    raise SystemExit(f"Invalid release version: {version}")
if not build.isdigit():
    raise SystemExit(f"Invalid release build: {build}")

for relative_path in ("api/download.js", "apps/web/api/download.js"):
    source = (ROOT / relative_path).read_text()
    handler_version = re.search(r'const DEFAULT_RELEASE_VERSION = "([^"]+)";', source)
    handler_location = re.search(r'const DEFAULT_RELEASE_LOCATION =\s*"([^"]+)";', source)
    if handler_version is None or handler_version.group(1) != version:
        raise SystemExit(f"{relative_path} version does not match {version}")
    if handler_location is None or not handler_location.group(1).endswith(f"/ShoutOut-{version}.dmg"):
        raise SystemExit(f"{relative_path} download URL does not match {version}")

index_source = (ROOT / "apps/web/index.html").read_text()
tracked_versions = set(re.findall(r'data-track-release-version="([^"]+)"', index_source))
local_downloads = set(re.findall(r'data-local-download-href="([^"]+)"', index_source))
if tracked_versions != {version}:
    raise SystemExit(f"Landing-page analytics versions do not match {version}: {tracked_versions}")
if local_downloads != {f"/releases/ShoutOut-{version}.dmg"}:
    raise SystemExit(f"Landing-page download paths do not match {version}: {local_downloads}")

notes_path = ROOT / f"apps/web/public/releases/ShoutOut-{version}.md"
if not notes_path.is_file() or not notes_path.read_text().startswith(f"# ShoutOut {version}\n"):
    raise SystemExit(f"Release notes are missing or mislabeled for {version}")

print(f"ok - release metadata agrees on ShoutOut {version} build {build}")
