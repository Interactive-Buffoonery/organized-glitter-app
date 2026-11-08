#!/usr/bin/env python3
"""Exercise stale-build rejection and HTTPS artifact delivery without live mutation."""
import copy
import hashlib
import importlib.util
import io
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
from unittest.mock import Mock, patch

sys.dont_write_bytecode = True
spec = importlib.util.spec_from_file_location("finish_update", Path(__file__).with_name("finish-update.py"))
update = importlib.util.module_from_spec(spec)
spec.loader.exec_module(update)
HEAD = "a" * 40
BID = "2b00b2d4-0bcb-47b7-950e-c28ecad14190"
PROJECT = Path("/owned/ios/OrganizedGlitter.xcodeproj")
ORIGIN = "https://example.invalid"


class HTTPBody(io.BytesIO):
    def seek(self, *args):
        raise io.UnsupportedOperation("HTTP responses are not seekable")

    def tell(self):
        raise io.UnsupportedOperation("HTTP responses have no file position")


class UpdateTests(unittest.TestCase):
    def setUp(self):
        self.job = {"id": BID, "state": "succeeded", "source_revision": HEAD, "source_dirty": False,
                    "request": {"project": str(PROJECT), "scheme": "OrganizedGlitter", "configuration": "Debug",
                                "mode": "archive", "allow_provisioning_updates": False},
                    "output": {"bundle_id": "com.interactivebuffoonery.organizedglitter", "ipa_path": "/owned/export/app.ipa"}}

    def test_exact_successful_build(self):
        self.assertEqual(update.validate_job(self.job, BID, HEAD, PROJECT), Path("/owned/export/app.ipa"))

    def test_old_failed_dirty_or_unknown_builds_are_rejected(self):
        for field, value in [("id", "old"), ("source_revision", "b" * 40), ("source_dirty", True),
                             ("source_dirty", None), ("state", "failed"), ("state", "running"),
                             ("state", "cancelled"), ("state", "interrupted")]:
            with self.subTest(field=field, value=value):
                job = copy.deepcopy(self.job)
                job[field] = value
                with self.assertRaises(update.VerificationError):
                    update.validate_job(job, BID, HEAD, PROJECT)

    def test_wrong_recipe_is_rejected(self):
        for field, value in [("project", "/other/app.xcodeproj"), ("scheme", "Other"),
                             ("configuration", "Release"), ("mode", "simulator"),
                             ("allow_provisioning_updates", True), ("allow_provisioning_updates", None),
                             ("no_overlay", True)]:
            with self.subTest(field=field, value=value):
                job = copy.deepcopy(self.job)
                job["request"][field] = value
                with self.assertRaises(update.VerificationError):
                    update.validate_job(job, BID, HEAD, PROJECT)

    def test_wrong_bundle_is_rejected(self):
        self.job["output"]["bundle_id"] = "other"
        with self.assertRaises(update.VerificationError):
            update.validate_job(self.job, BID, HEAD, PROJECT)

    def test_origin_boundary(self):
        self.assertEqual(update.same_origin(ORIGIN + "/install/ticket", ORIGIN), ORIGIN + "/install/ticket")
        for url in ["http://example.invalid/a", "https://other.invalid/a", "https://example.invalid:8443/a",
                    "https://user:password@example.invalid/a", ORIGIN + "/a#fragment"]:
            with self.subTest(url=url), self.assertRaises(update.VerificationError):
                update.same_origin(url, ORIGIN)

    def test_redirects_are_not_followed(self):
        self.assertIsNone(update.NoRedirects().redirect_request(None, None, 302, "", {}, "https://other.invalid"))

    def delivery(self, downloaded, digest, asset=ORIGIN + "/ipa", linked_id=BID):
        manifest = plistlib.dumps({"items": [{"assets": [{"kind": "software-package", "url": asset}]}]})
        def response(data):
            stream = HTTPBody(data)
            stream.status = 200
            return stream
        opener = Mock()
        opener.open.side_effect = [response(b"page"), response(manifest), response(downloaded)]
        links = {"build_id": linked_id, "page_url": ORIGIN + "/install/ticket", "manifest_url": ORIGIN + "/manifest"}
        with patch.object(update, "build_opener", return_value=opener):
            update.verify_delivery(links, BID, digest, ORIGIN)
        return opener

    def test_downloaded_bytes_must_match_export(self):
        data = b"signed export fixture"
        self.assertEqual(self.delivery(data, hashlib.sha256(data).hexdigest()).open.call_count, 3)
        with self.assertRaises(update.VerificationError):
            self.delivery(b"old IPA", hashlib.sha256(data).hexdigest())

    def test_manifest_cannot_change_origin(self):
        with self.assertRaises(update.VerificationError):
            self.delivery(b"ipa", "unused", asset="https://other.invalid/ipa")

    def test_install_link_cannot_substitute_build(self):
        with self.assertRaises(update.VerificationError):
            self.delivery(b"ipa", "unused", linked_id="old")

    def test_receipts_are_private_even_when_replacing_existing_file(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "receipt.json"
            path.touch(mode=0o644)
            update.write_receipt(path, {"build_id": BID})
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            link = Path(directory) / "link.json"
            link.symlink_to(path)
            with self.assertRaises(OSError):
                update.write_receipt(link, {"build_id": "wrong"})


if __name__ == "__main__":
    unittest.main()
