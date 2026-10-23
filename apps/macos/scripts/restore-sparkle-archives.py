#!/usr/bin/env python3
"""Restore signed release archives so fresh checkouts can generate delta updates."""

import argparse
import os
from pathlib import Path
import re
import subprocess
import tempfile
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET


SPARKLE = "{http://www.andymatuschak.org/xml-namespaces/sparkle}"


def find_archives(feed_path, current_build, maximum_deltas):
    archives = []
    for item in ET.parse(feed_path).getroot().findall("./channel/item"):
        build = item.findtext(f"{SPARKLE}version", "")
        enclosure = item.find("enclosure")
        if not build.isdigit() or int(build) >= current_build or enclosure is None:
            continue
        url = enclosure.get("url", "")
        filename = urllib.parse.unquote(Path(urllib.parse.urlsplit(url).path).name)
        size = enclosure.get("length", "")
        signature = enclosure.get(f"{SPARKLE}edSignature", "")
        if (
            urllib.parse.urlsplit(url).scheme != "https"
            or not re.fullmatch(r"ShoutOut-[0-9.]+\.(dmg|zip)", filename)
            or not size.isdigit()
            or int(size) <= 0
            or not signature
        ):
            raise ValueError(f"Invalid baseline archive for build {build}")
        archives.append((int(build), filename, url, int(size), signature))
    return sorted(archives, reverse=True)[:maximum_deltas]


def verify_archive(path, size, signature, sign_update, account):
    if path.stat().st_size != size:
        raise ValueError(f"Archive length mismatch: {path.name}")
    command = [str(sign_update), "--account", account, "--verify"]
    private_key = os.environ.get("SPARKLE_PRIVATE_ED_KEY")
    if private_key:
        command += ["--ed-key-file", "-"]
    subprocess.run(
        command + [str(path), signature],
        input=private_key,
        text=True,
        check=True,
    )


def restore_archive(archive, archives_dir, sign_update, account):
    _, filename, url, size, signature = archive
    destination = archives_dir / filename
    if destination.exists():
        verify_archive(destination, size, signature, sign_update, account)
        return
    print(f"Restoring delta baseline: {filename}", flush=True)
    descriptor, temporary_path = tempfile.mkstemp(dir=archives_dir, suffix=".download")
    temporary_path = Path(temporary_path)
    try:
        with os.fdopen(descriptor, "wb") as output:
            with urllib.request.urlopen(url, timeout=60) as response:
                if urllib.parse.urlsplit(response.url).scheme != "https":
                    raise ValueError("Baseline download redirected away from HTTPS")
                total = 0
                while chunk := response.read(1024 * 1024):
                    total += len(chunk)
                    if total > size:
                        raise ValueError(f"Archive exceeds expected length: {filename}")
                    output.write(chunk)
        verify_archive(temporary_path, size, signature, sign_update, account)
        temporary_path.replace(destination)
    finally:
        temporary_path.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--feed", type=Path, required=True)
    parser.add_argument("--archives", type=Path, required=True)
    parser.add_argument("--build", type=int, required=True)
    parser.add_argument("--maximum-deltas", type=int, default=5)
    parser.add_argument("--sign-update", type=Path, required=True)
    parser.add_argument("--account", default="ed25519")
    args = parser.parse_args()
    if args.maximum_deltas < 0:
        parser.error("--maximum-deltas must be nonnegative")
    args.archives.mkdir(parents=True, exist_ok=True)
    for archive in find_archives(args.feed, args.build, args.maximum_deltas):
        restore_archive(archive, args.archives, args.sign_update, args.account)


if __name__ == "__main__":
    main()
