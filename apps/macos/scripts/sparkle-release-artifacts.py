#!/usr/bin/env python3
"""Keep Sparkle generation, artifact upload, and feed staging in agreement."""

import argparse
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET


SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"
DEFAULT_R2_BUCKET = "shoutout-releases"
DEFAULT_URL_PREFIX = "https://downloads.shoutout.sh/releases/"
CACHE_CONTROL = "public, max-age=31536000, immutable"


def prepare_manifest(archives, public, version, bucket=DEFAULT_R2_BUCKET, url_prefix=DEFAULT_URL_PREFIX):
    archives = archives.resolve()
    feed = archives / "appcast.xml"
    item = ET.parse(feed).getroot().find("./channel/item")
    if item is None or item.findtext(f"{SPARKLE}shortVersionString") != version:
        raise ValueError("Generated appcast does not start with the current release")
    assets = []
    for enclosure in [item.find("enclosure"), *item.findall(f"{SPARKLE}deltas/enclosure")]:
        if enclosure is None or not enclosure.get(f"{SPARKLE}edSignature"):
            raise ValueError("Missing signed release enclosure")
        url = enclosure.get("url", "")
        filename = Path(urllib.parse.urlsplit(url).path).name
        path = archives / filename
        if not path.is_file() or path.stat().st_size != int(enclosure.get("length", "0")):
            raise ValueError(f"Missing or incorrect release artifact: {filename}")
        assets.append({"path": str(path), "url": url, "size": path.stat().st_size})
    notes_url = item.findtext(f"{SPARKLE}releaseNotesLink", "")
    notes = archives / f"ShoutOut-{version}.md"
    if not notes_url or Path(urllib.parse.urlsplit(notes_url).path).name != notes.name:
        raise ValueError("Release notes URL does not match the current release")
    assets.append({"path": str(notes), "url": notes_url, "size": notes.stat().st_size})
    return {
        "feed": str(feed), "public": str(public.resolve()), "assets": assets,
        "r2_bucket": bucket, "url_prefix": url_prefix,
    }


def stage_release(manifest):
    public = Path(manifest["public"])
    releases = public / "releases"
    releases.mkdir(parents=True, exist_ok=True)
    for asset in manifest["assets"]:
        shutil.copy2(asset["path"], releases / Path(asset["path"]).name)
    # The feed becomes deployable only after every referenced new file is staged.
    descriptor, temporary_path = tempfile.mkstemp(dir=public, suffix=".xml")
    os.close(descriptor)
    try:
        shutil.copy2(manifest["feed"], temporary_path)
        os.replace(temporary_path, public / "appcast.xml")
    finally:
        Path(temporary_path).unlink(missing_ok=True)


def upload_release(manifest):
    bucket = manifest["r2_bucket"]
    prefix = manifest["url_prefix"]
    prefix_url = urllib.parse.urlsplit(prefix)
    if (
        not re.fullmatch(r"[a-z0-9][a-z0-9-]*[a-z0-9]", bucket)
        or prefix_url.scheme != "https" or not prefix_url.hostname
        or prefix_url.username or prefix_url.password or prefix_url.port
        or prefix_url.path != "/releases/"
        or prefix_url.query or prefix_url.fragment
    ):
        raise ValueError("Invalid R2 bucket or public releases URL prefix")
    for asset in manifest["assets"]:
        expected_url = prefix + Path(asset["path"]).name
        if asset["url"] != expected_url:
            raise ValueError(f"Artifact URL does not match the R2 upload destination: {asset['url']}")
    for asset in manifest["assets"]:
        path = Path(asset["path"])
        content_type = {".dmg": "application/x-apple-diskimage", ".md": "text/markdown"}.get(
            path.suffix, "application/octet-stream"
        )
        subprocess.run(
            ["npx", "wrangler", "r2", "object", "put", f"{bucket}/releases/{path.name}",
             "--file", str(path), "--content-type", content_type,
             "--cache-control", CACHE_CONTROL, "--remote"],
            check=True,
        )
    for asset in manifest["assets"]:
        request = urllib.request.Request(
            asset["url"], method="HEAD", headers={"User-Agent": "ShoutOut-release-tools/1.0"}
        )
        with urllib.request.urlopen(request, timeout=60) as response:
            if int(response.headers.get("Content-Length", "0")) != asset["size"]:
                raise ValueError(f"Uploaded artifact length mismatch: {asset['url']}")
    stage_release(manifest)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    prepare = subparsers.add_parser("prepare")
    prepare.add_argument("--archives", type=Path, required=True)
    prepare.add_argument("--public", type=Path, required=True)
    prepare.add_argument("--version", required=True)
    prepare.add_argument("--output", type=Path, required=True)
    prepare.add_argument("--r2-bucket", default=DEFAULT_R2_BUCKET)
    prepare.add_argument("--url-prefix", default=DEFAULT_URL_PREFIX)
    for command in ["stage", "upload"]:
        subparser = subparsers.add_parser(command)
        subparser.add_argument("manifest", type=Path)
    args = parser.parse_args()
    if args.command == "prepare":
        manifest = prepare_manifest(
            args.archives, args.public, args.version, args.r2_bucket, args.url_prefix
        )
        args.output.write_text(json.dumps(manifest, indent=2) + "\n")
    else:
        manifest = json.loads(args.manifest.read_text())
        if args.command == "upload":
            upload_release(manifest)
        else:
            stage_release(manifest)


if __name__ == "__main__":
    main()
