#!/usr/bin/env python3
"""Prepare an isolated, pinned upstream checkout; never modifies T3 or signing."""
import argparse
from pathlib import Path
import subprocess

PIN = "737f2e881483a4c7237b49d5696adff7d44cad1b"
ROOT = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("destination", type=Path)
parser.add_argument("--source", default="https://github.com/achimala/Squircle.git")
args = parser.parse_args()
if args.destination.exists():
    parser.error("destination must not exist; preserve existing checkouts")
subprocess.run(["git", "clone", "--no-checkout", args.source, str(args.destination)], check=True)
subprocess.run(["git", "-C", str(args.destination), "checkout", "--detach", PIN], check=True)
subprocess.run(["git", "-C", str(args.destination), "apply", "--check", str(ROOT / "integration.patch")], check=True)
subprocess.run(["git", "-C", str(args.destination), "apply", str(ROOT / "integration.patch")], check=True)
(args.destination / "app/Squircle/Sources/DeveloperEnrollment.swift").write_bytes((ROOT / "DeveloperEnrollment.swift").read_bytes())
print("Prepared pinned upstream with developer policy. No service started or signing changed.")
