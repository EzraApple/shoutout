#!/usr/bin/env python3
"""Verify and stage the three frozen Mini cleanup assets."""

import argparse
import hashlib
import pathlib
import shutil
import sys
import tempfile
import urllib.request
import zipfile


VOCAB_SHA256 = "07eced375cec144d27c900241f3e339478dec958f92fddbc551f295c992038a3"
CONFIG_SHA256 = "7a248d081af1990bbbb20e98f58f07759f13991aec65a97858bdfd593697efc8"
PACKAGE_SHA256 = "6c62bb511b9f639998907e578b062d1932e6c79ad55dea6c94fa47f79edc93f5"
ARCHIVE_URL = "https://xhahmepifrbmvgrg.public.blob.vercel-storage.com/models/native-mini-2026-10-21-fc95c7a39849.zip"
ARCHIVE_SHA256 = "fc95c7a39849854d900dc02e364cc3675175810e589c0ba7a5a8407892b50791"


def file_sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1_048_576), b""):
            digest.update(chunk)
    return digest.hexdigest()


def package_sha256(root: pathlib.Path) -> str:
    digest = hashlib.sha256()
    for path in sorted(root.rglob("*")):
        if path.is_symlink():
            raise ValueError(f"Mini package contains a symlink: {path}")
        if path.is_dir():
            continue
        if not path.is_file():
            raise ValueError(f"Mini package contains an unsupported entry: {path}")
        digest.update(path.relative_to(root).as_posix().encode())
        with path.open("rb") as source:
            for chunk in iter(lambda: source.read(1_048_576), b""):
                digest.update(chunk)
    return digest.hexdigest()


def verify(root: pathlib.Path) -> None:
    if not root.is_absolute() or not root.is_dir() or root.is_symlink():
        raise ValueError("Mini asset directory must be an absolute, non-symlink directory")
    package = root / "mini-fixed256.mlpackage"
    vocab = root / "vocab.txt"
    config = root / "tokenizer-config.json"
    if package.is_symlink() or not package.is_dir():
        raise ValueError("Frozen Mini model package is missing or is a symlink")
    for path in (vocab, config):
        if path.is_symlink() or not path.is_file():
            raise ValueError(f"Frozen Mini asset is missing or is a symlink: {path.name}")
    if file_sha256(vocab) != VOCAB_SHA256:
        raise ValueError("Mini vocabulary hash differs from the frozen model")
    if file_sha256(config) != CONFIG_SHA256:
        raise ValueError("Mini tokenizer config hash differs from the frozen model")
    if package_sha256(package) != PACKAGE_SHA256:
        raise ValueError("Mini package hash differs from the frozen model")


def stage(source: pathlib.Path, destination: pathlib.Path) -> None:
    verify(source)
    if not destination.is_absolute() or destination.exists() or destination.is_symlink():
        raise ValueError("Mini asset destination must be a new absolute directory")
    if not destination.parent.is_dir() or destination.parent.is_symlink():
        raise ValueError("Mini asset destination parent is missing or is a symlink")
    with tempfile.TemporaryDirectory(prefix=".mini-assets-", dir=destination.parent) as temporary:
        staged = pathlib.Path(temporary)
        shutil.copytree(source / "mini-fixed256.mlpackage", staged / "mini-fixed256.mlpackage")
        shutil.copy2(source / "vocab.txt", staged / "vocab.txt")
        shutil.copy2(source / "tokenizer-config.json", staged / "tokenizer-config.json")
        verify(staged)
        staged.rename(destination)


def fetch(destination: pathlib.Path) -> None:
    if not destination.is_absolute() or destination.is_symlink():
        raise ValueError("Mini asset destination must be an absolute, non-symlink directory")
    if destination.exists():
        verify(destination)
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=".mini-download-", dir=destination.parent) as temporary:
        root = pathlib.Path(temporary)
        archive = root / "model.zip"
        with urllib.request.urlopen(ARCHIVE_URL, timeout=120) as response, archive.open("wb") as output:
            shutil.copyfileobj(response, output)
        if file_sha256(archive) != ARCHIVE_SHA256:
            raise ValueError("Mini download hash differs from the frozen archive")
        extracted = root / "extracted"
        extracted.mkdir()
        with zipfile.ZipFile(archive) as source:
            for entry in source.infolist():
                path = pathlib.PurePosixPath(entry.filename)
                if path.is_absolute() or ".." in path.parts:
                    raise ValueError("Mini archive contains an invalid path")
                if path.parts[0] not in ("mini-fixed256.mlpackage", "vocab.txt", "tokenizer-config.json", "MiniCleanupNotices"):
                    raise ValueError("Mini archive contains an unexpected asset")
            source.extractall(extracted)
        stage(extracted, destination)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=("verify", "stage", "fetch"))
    parser.add_argument("source", type=pathlib.Path)
    parser.add_argument("destination", type=pathlib.Path, nargs="?")
    args = parser.parse_args()
    if args.command == "fetch":
        if args.destination is not None:
            parser.error("fetch accepts only a destination directory")
        fetch(args.source)
    elif args.command == "stage":
        if args.destination is None:
            parser.error("stage requires a destination directory")
        stage(args.source, args.destination)
    else:
        if args.destination is not None:
            parser.error("verify does not accept a destination")
        verify(args.source)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError) as error:
        print(f"Mini asset check failed: {error}", file=sys.stderr)
        sys.exit(1)
