#!/usr/bin/env python3
"""Verify one managed personal update before offering its expiring install link."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import plistlib
import subprocess
import tempfile
from urllib.parse import urlsplit
from urllib.request import HTTPRedirectHandler, build_opener
import uuid


class VerificationError(Exception):
    pass


def require(condition, message):
    if not condition:
        raise VerificationError(message)


def validate_job(job, build_id, head, project):
    require(job.get("id") == build_id, "Build ID mismatch")
    require(job.get("state") == "succeeded", "Build did not succeed")
    require(job.get("source_revision") == head, "Build source revision mismatch")
    require(job.get("source_dirty") is False, "Build source was dirty or unknown")
    request = job.get("request", {})
    require(Path(request.get("project", "")).resolve() == project.resolve(), "Project mismatch")
    require(request.get("scheme") == "OrganizedGlitter", "Scheme mismatch")
    require(request.get("configuration") == "Debug" and request.get("mode") == "archive", "Not a personal Debug archive")
    require(request.get("allow_provisioning_updates") is False, "Provisioning updates enabled or unknown")
    require(not request.get("no_overlay", False), "Overlay was disabled")
    output = job.get("output", {})
    require(output.get("bundle_id") == "com.interactivebuffoonery.organizedglitter", "Bundle ID mismatch")
    return Path(output["ipa_path"])


def same_origin(url, origin):
    parsed, expected = urlsplit(url), urlsplit(origin)
    require(parsed.scheme == expected.scheme == "https", "HTTPS required")
    require(parsed.hostname is not None and parsed.hostname == expected.hostname and
            (parsed.port or 443) == (expected.port or 443), "Delivery origin mismatch")
    require(parsed.username is None and parsed.password is None and not parsed.fragment, "Invalid delivery URL")
    return url


class NoRedirects(HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def verify_delivery(links, build_id, digest, origin):
    require(links.get("build_id") == build_id, "Install link build ID mismatch")
    opener = build_opener(NoRedirects())
    with opener.open(same_origin(links["page_url"], origin), timeout=30) as response:
        require(response.status == 200, "Install page unavailable")
    with opener.open(same_origin(links["manifest_url"], origin), timeout=30) as response:
        manifest = plistlib.loads(response.read())
    assets = [asset["url"] for item in manifest["items"] for asset in item["assets"] if asset["kind"] == "software-package"]
    require(len(assets) == 1, "Expected one IPA download")
    downloaded = hashlib.sha256()
    with opener.open(same_origin(assets[0], origin), timeout=60) as response:
        while chunk := response.read(1024 * 1024):
            downloaded.update(chunk)
    require(downloaded.hexdigest() == digest, "Downloaded IPA differs from signed export")


def verify_artifact(ipa, build_id, coordinator):
    with tempfile.TemporaryDirectory(prefix="og-update-") as directory:
        subprocess.run(["ditto", "-x", "-k", str(ipa), directory], check=True, capture_output=True)
        apps = list((Path(directory) / "Payload").glob("*.app"))
        require(len(apps) == 1, "Expected one exported app")
        app = apps[0]
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True, capture_output=True)
        info = plistlib.loads((app / "Info.plist").read_bytes())
        require(info.get("SquircleBuildID") == build_id, "Embedded build ID mismatch")
        require(info.get("CFBundleIdentifier") == "com.interactivebuffoonery.organizedglitter", "Exported bundle mismatch")
        executable = app / info["CFBundleExecutable"]
        links = subprocess.check_output(["otool", "-L", str(executable)], text=True)
        require("@executable_path/Frameworks/SquircleOverlay.framework/SquircleOverlay" in links, "Overlay linkage missing")
        framework = app / "Frameworks/SquircleOverlay.framework/SquircleOverlay"
        require(coordinator.encode() in framework.read_bytes(), "Dedicated chat missing from overlay")
        require(subprocess.check_output(["lipo", "-archs", str(executable)], text=True).strip() == "arm64", "Expected arm64 export")
        entitlements = plistlib.loads(subprocess.check_output(["codesign", "-d", "--entitlements", ":-", str(app)], stderr=subprocess.DEVNULL))
        require(entitlements.get("get-task-allow") is True, "Expected development signing")
        require(not any(p.name in {"client.json", "client-t3.json", "Developer enrollment.json"} for p in app.rglob("*.json")), "Enrollment resource bundled")
    with ipa.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def write_receipt(path, receipt):
    path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    with open(path, "w", opener=lambda name, flags: os.open(name, flags | os.O_NOFOLLOW, 0o600)) as stream:
        os.fchmod(stream.fileno(), 0o600)
        json.dump(receipt, stream, indent=2)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--build-id", required=True)
    parser.add_argument("--head", required=True)
    parser.add_argument("--root", type=Path, default=Path.home() / "Library/Application Support/OrganizedGlitterDeveloper")
    parser.add_argument("--origin", required=True, help="Existing approved HTTPS service origin")
    parser.add_argument("--receipt", type=Path, required=True, help="Private receipt path; includes an expiring install ticket")
    args = parser.parse_args()
    require(str(uuid.UUID(args.build_id)) == args.build_id, "Expected managed build UUID")
    require(len(args.head) == 40 and all(c in "0123456789abcdef" for c in args.head), "Expected full source SHA")
    repo = Path(__file__).resolve().parents[2]
    require(not args.receipt.resolve().is_relative_to(repo), "Receipt must stay outside the checkout")
    base = [str(args.root / "bin/squircle"), "--data-dir", str(args.root / "state"), "--json"]

    def cli(*command):
        result = subprocess.run(base + list(command), check=True, capture_output=True, text=True)
        response = json.loads(result.stdout)
        require(response.get("ok") is True, "Squircle command failed")
        return response["data"]

    job = cli("build", "status", args.build_id)["job"]
    ipa = validate_job(job, args.build_id, args.head, repo / "ios/OrganizedGlitter.xcodeproj")
    enrollment = (repo / "developer/squircle/DeveloperEnrollment.swift").read_text()
    coordinator = enrollment.split('static let coordinator = "', 1)[1].split('"', 1)[0]
    digest = verify_artifact(ipa, args.build_id, coordinator)
    links = cli("install-link", args.build_id, "--ttl-seconds", "3600")
    verify_delivery(links, args.build_id, digest, args.origin)
    receipt = {"source_head": args.head, "build_id": args.build_id, "ipa_sha256": digest,
               "signature_and_delivery_verified": True, "physical_launch_verified": False,
               "page_url": links["page_url"], "expires_at": links["expires_at"]}
    write_receipt(args.receipt, receipt)
    print(json.dumps(receipt))


if __name__ == "__main__":
    try:
        main()
    except (VerificationError, subprocess.CalledProcessError, OSError, KeyError, ValueError):
        raise SystemExit("Update verification failed; do not offer an older build. Inspect local build diagnostics privately.")
