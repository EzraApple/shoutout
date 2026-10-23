#!/usr/bin/env python3
"""Check delta baseline selection, signature checks, and atomic downloads."""

import importlib.util
import io
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parent.parent
sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location(
    "archives", ROOT / "apps/macos/scripts/restore-sparkle-archives.py"
)
archives = importlib.util.module_from_spec(spec)
spec.loader.exec_module(archives)
artifact_spec = importlib.util.spec_from_file_location(
    "artifacts", ROOT / "apps/macos/scripts/sparkle-release-artifacts.py"
)
artifacts = importlib.util.module_from_spec(artifact_spec)
artifact_spec.loader.exec_module(artifacts)


def feed_item(build, filename=None, size=4, signature="signed"):
    filename = filename or f"ShoutOut-0.1.{build}.dmg"
    return (
        f"<item><sparkle:version>{build}</sparkle:version>"
        f'<enclosure url="https://example.com/{filename}" length="{size}" '
        f'sparkle:edSignature="{signature}"/></item>'
    )


class ArchiveTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.feed = self.directory / "appcast.xml"

    def write_feed(self, items):
        self.feed.write_text(
            '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">'
            f"<channel>{''.join(items)}</channel></rss>"
        )

    def test_selects_recent_older_builds_and_excludes_current_and_future(self):
        self.write_feed([feed_item(build) for build in [1, 4, 3, 5, 2]])
        selected = archives.find_archives(self.feed, 4, 2)
        self.assertEqual([item[0] for item in selected], [3, 2])
        self.assertEqual(archives.find_archives(self.feed, 4, 0), [])

    def test_rejects_unsafe_filename_or_missing_signature(self):
        for filename, signature in [("ShoutOut-%2Fbad.dmg", "signed"), (None, "")]:
            with self.subTest(filename=filename, signature=signature):
                self.write_feed([feed_item(1, filename, signature=signature)])
                with self.assertRaises(ValueError):
                    archives.find_archives(self.feed, 2, 5)

    def test_download_verifies_before_promoting_and_reuses_valid_archive(self):
        self.write_feed([feed_item(1)])
        archive = archives.find_archives(self.feed, 2, 5)[0]
        response = io.BytesIO(b"data")
        response.url = archive[2]
        with patch.object(archives.urllib.request, "urlopen", return_value=response) as download:
            with patch.object(archives.subprocess, "run") as verify:
                with patch.dict(archives.os.environ, {}, clear=True):
                    archives.restore_archive(archive, self.directory, Path("sign_update"), "test")
                    destination = self.directory / archive[1]
                    self.assertEqual(destination.read_bytes(), b"data")
                    self.assertIn("--verify", verify.call_args.args[0])
                    self.assertEqual(verify.call_args.args[0][-1], "signed")
                    archives.restore_archive(archive, self.directory, Path("sign_update"), "test")
                self.assertEqual(verify.call_count, 2)
                self.assertEqual(download.call_count, 1)

    def test_invalid_download_is_not_saved(self):
        self.write_feed([feed_item(1)])
        archive = archives.find_archives(self.feed, 2, 5)[0]
        for data, verify_error in [(b"too long", None), (b"bad", None), (b"data", subprocess.CalledProcessError(1, "verify"))]:
            with self.subTest(data=data):
                response = io.BytesIO(data)
                response.url = archive[2]
                with patch.object(archives.urllib.request, "urlopen", return_value=response):
                    with patch.object(archives.subprocess, "run", side_effect=verify_error):
                        with self.assertRaises((ValueError, subprocess.CalledProcessError)):
                            archives.restore_archive(archive, self.directory, Path("sign_update"), "test")
                self.assertFalse((self.directory / archive[1]).exists())
                self.assertEqual(list(self.directory.glob("*.download")), [])

    def test_private_key_uses_stdin(self):
        archive = self.directory / "archive.dmg"
        archive.write_bytes(b"data")
        with patch.dict(archives.os.environ, {"SPARKLE_PRIVATE_ED_KEY": "test-private-key"}):
            with patch.object(archives.subprocess, "run") as verify:
                archives.verify_archive(archive, 4, "signed", Path("sign_update"), "test")
                self.assertNotIn("test-private-key", verify.call_args.args[0])
                self.assertEqual(verify.call_args.kwargs["input"], "test-private-key")
                self.assertIn("--ed-key-file", verify.call_args.args[0])


class ArtifactTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.directory = Path(self.temporary.name)
        self.public = self.directory / "public"
        self.public.mkdir()
        self.feed = self.directory / "appcast.xml"
        self.feed.write_text("new feed")
        self.assets = []
        for filename in ["ShoutOut-0.3.1.dmg", "ShoutOut22-21.delta", "ShoutOut-0.3.1.md"]:
            path = self.directory / filename
            path.write_bytes(b"data")
            self.assets.append({
                "path": str(path), "size": 4,
                "url": f"https://downloads.shoutout.sh/releases/{filename}",
            })
        self.manifest = {
            "feed": str(self.feed), "public": str(self.public), "assets": self.assets,
            "r2_bucket": "shoutout-releases",
            "url_prefix": "https://downloads.shoutout.sh/releases/",
        }

    def test_failed_upload_keeps_existing_feed(self):
        (self.public / "appcast.xml").write_text("old feed")
        with patch.object(artifacts.subprocess, "run", side_effect=subprocess.CalledProcessError(1, "upload")):
            with self.assertRaises(subprocess.CalledProcessError):
                artifacts.upload_release(self.manifest)
        self.assertEqual((self.public / "appcast.xml").read_text(), "old feed")

    def test_mismatched_url_fails_before_upload(self):
        self.assets[-1]["url"] = "https://downloads.shoutout.sh/elsewhere/notes.md"
        with patch.object(artifacts.subprocess, "run") as upload:
            with self.assertRaises(ValueError):
                artifacts.upload_release(self.manifest)
            upload.assert_not_called()

    def test_invalid_bucket_fails_before_upload(self):
        self.manifest["r2_bucket"] = "other-bucket/releases"
        with patch.object(artifacts.subprocess, "run") as upload:
            with self.assertRaises(ValueError):
                artifacts.upload_release(self.manifest)
            upload.assert_not_called()

    def test_successful_upload_verifies_lengths_then_stages_feed_and_patch(self):
        def public_response(*args, **kwargs):
            response = io.BytesIO()
            response.headers = {"Content-Length": "4"}
            return response

        with patch.object(artifacts.subprocess, "run") as upload:
            with patch.object(artifacts.urllib.request, "urlopen", side_effect=public_response):
                artifacts.upload_release(self.manifest)
        self.assertEqual(upload.call_count, 3)
        self.assertEqual(
            [call.args[0][5] for call in upload.call_args_list],
            [f"shoutout-releases/releases/{Path(asset['path']).name}" for asset in self.assets],
        )
        for asset, call in zip(self.assets, upload.call_args_list):
            command = call.args[0]
            self.assertEqual(command[:5], ["npx", "wrangler", "r2", "object", "put"])
            self.assertIn("--remote", command)
            self.assertEqual(command[command.index("--cache-control") + 1], artifacts.CACHE_CONTROL)
            self.assertEqual(command[command.index("--file") + 1], asset["path"])
            expected_type = "text/markdown" if asset["path"].endswith(".md") else (
                "application/x-apple-diskimage" if asset["path"].endswith(".dmg")
                else "application/octet-stream"
            )
            self.assertEqual(command[command.index("--content-type") + 1], expected_type)
        self.assertEqual((self.public / "appcast.xml").read_text(), "new feed")
        self.assertEqual((self.public / "releases/ShoutOut22-21.delta").read_bytes(), b"data")

    def test_wrong_public_length_does_not_stage_feed(self):
        response = io.BytesIO()
        response.headers = {"Content-Length": "3"}
        with patch.object(artifacts.subprocess, "run"):
            with patch.object(artifacts.urllib.request, "urlopen", return_value=response):
                with self.assertRaises(ValueError):
                    artifacts.upload_release(self.manifest)
        self.assertFalse((self.public / "appcast.xml").exists())

    def test_failed_public_head_does_not_stage_feed(self):
        with patch.object(artifacts.subprocess, "run"):
            with patch.object(artifacts.urllib.request, "urlopen", side_effect=OSError("unavailable")):
                with self.assertRaises(OSError):
                    artifacts.upload_release(self.manifest)
        self.assertFalse((self.public / "appcast.xml").exists())

    def test_manifest_includes_only_referenced_patches_and_rejects_missing_patch(self):
        (self.directory / "ShoutOut-old.delta").write_bytes(b"unused")
        prefix = "https://downloads.shoutout.sh/releases/"
        self.feed.write_text(
            '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>'
            '<sparkle:shortVersionString>0.3.1</sparkle:shortVersionString>'
            f'<enclosure url="{prefix}ShoutOut-0.3.1.dmg" length="4" sparkle:edSignature="sig"/>'
            '<sparkle:deltas>'
            f'<enclosure url="{prefix}ShoutOut22-21.delta" length="4" sparkle:edSignature="sig"/>'
            '</sparkle:deltas>'
            f'<sparkle:releaseNotesLink>{prefix}ShoutOut-0.3.1.md</sparkle:releaseNotesLink>'
            '</item></channel></rss>'
        )
        manifest = artifacts.prepare_manifest(self.directory, self.public, "0.3.1")
        self.assertEqual(len(manifest["assets"]), 3)
        self.assertEqual(manifest["r2_bucket"], "shoutout-releases")
        self.assertEqual(manifest["url_prefix"], prefix)
        self.assertTrue(all(Path(asset["path"]).is_absolute() for asset in manifest["assets"]))
        self.assertEqual({Path(asset["path"]).name for asset in manifest["assets"]}, {
            "ShoutOut-0.3.1.dmg", "ShoutOut22-21.delta", "ShoutOut-0.3.1.md",
        })
        (self.directory / "ShoutOut22-21.delta").unlink()
        with self.assertRaises(ValueError):
            artifacts.prepare_manifest(self.directory, self.public, "0.3.1")

    def test_manifest_cli_records_bucket_override(self):
        self.feed.write_text(
            '<rss xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle"><channel><item>'
            '<sparkle:shortVersionString>0.3.1</sparkle:shortVersionString>'
            '<enclosure url="https://cdn.example.com/releases/ShoutOut-0.3.1.dmg" length="4" '
            'sparkle:edSignature="sig"/>'
            '<sparkle:releaseNotesLink>https://cdn.example.com/releases/ShoutOut-0.3.1.md'
            '</sparkle:releaseNotesLink></item></channel></rss>'
        )
        output = self.directory / "manifest.json"
        with patch.object(sys, "argv", [
            "sparkle-release-artifacts.py", "prepare", "--archives", str(self.directory),
            "--public", str(self.public), "--version", "0.3.1", "--output", str(output),
            "--r2-bucket", "staging-releases", "--url-prefix", "https://cdn.example.com/releases/",
        ]):
            artifacts.main()
        manifest = json.loads(output.read_text())
        self.assertEqual(manifest["r2_bucket"], "staging-releases")
        self.assertEqual(manifest["url_prefix"], "https://cdn.example.com/releases/")


if __name__ == "__main__":
    unittest.main()
