#!/usr/bin/env python3
"""Keep Sparkle generation, artifact upload, and feed staging in agreement."""

import argparse
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET


SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def prepare_manifest(archives, public, version):
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
    return {"feed": str(feed), "public": str(public.resolve()), "assets": assets}


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
    # This command publishes to Vercel Blob. Other hosts can use the manifest
    # with their own uploader, then run the stage command.
    for asset in manifest["assets"]:
        url = urllib.parse.urlsplit(asset["url"])
        expected_path = f"/releases/{Path(asset['path']).name}"
        if (
            url.scheme != "https"
            or not url.netloc.endswith(".public.blob.vercel-storage.com")
            or url.path != expected_path
        ):
            raise ValueError(f"Artifact URL does not match the Blob upload destination: {asset['url']}")
    environment = dict(os.environ)
    environment.pop("VERCEL_OIDC_TOKEN", None)
    for asset in manifest["assets"]:
        path = Path(asset["path"])
        content_type = {".dmg": "application/x-apple-diskimage", ".md": "text/markdown"}.get(
            path.suffix, "application/octet-stream"
        )
        subprocess.run(
            ["npx", "vercel", "blob", "put", str(path), "--pathname", f"releases/{path.name}",
             "--access", "public", "--allow-overwrite", "true", "--content-type", content_type],
            env=environment, check=True,
        )
    for asset in manifest["assets"]:
        request = urllib.request.Request(asset["url"], method="HEAD")
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
    for command in ["stage", "upload"]:
        subparser = subparsers.add_parser(command)
        subparser.add_argument("manifest", type=Path)
    args = parser.parse_args()
    if args.command == "prepare":
        manifest = prepare_manifest(args.archives, args.public, args.version)
        args.output.write_text(json.dumps(manifest, indent=2) + "\n")
    else:
        manifest = json.loads(args.manifest.read_text())
        if args.command == "upload":
            upload_release(manifest)
        else:
            stage_release(manifest)


if __name__ == "__main__":
    main()
