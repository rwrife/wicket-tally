#!/usr/bin/env python3
"""Wait for the exact App Store Connect build created by this release run."""
import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime

BASE = "https://api.appstoreconnect.apple.com"


def parse_timestamp(s: str) -> datetime:
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    return datetime.fromisoformat(s)


def poll(key_path, key_id, issuer_id, bundle_id, version, build_number, started_at,
         deadline_seconds=1200, interval=30, request=None, clock=None, pause=None):
    """Return the processed build ID; never accept an older upload or another version."""
    request = request or urllib.request.urlopen
    clock = clock or time.time
    pause = pause or time.sleep
    started_dt = parse_timestamp(started_at)

    def fetch(resource, params):
        try:
            res = subprocess.run(
                [sys.executable, os.path.join(os.path.dirname(__file__), "asc_jwt.py"),
                 key_path, key_id, issuer_id],
                capture_output=True, text=True, timeout=15, check=True
            )
            token = res.stdout.strip()
        except (OSError, subprocess.SubprocessError):
            raise RuntimeError("Failed to generate App Store Connect JWT token") from None
        url = BASE + resource + "?" + urllib.parse.urlencode(params)
        req = urllib.request.Request(url, headers={"Authorization": "Bearer " + token})
        for attempt in range(3):
            try:
                with request(req, timeout=30) as response:
                    payload = json.load(response)
                    if not isinstance(payload.get("data"), (list, dict)):
                        raise ValueError("Missing data in App Store Connect response")
                    return payload["data"]
            except urllib.error.HTTPError as error:
                if error.code not in {429, 500, 502, 503, 504} or attempt == 2:
                    raise
            except (urllib.error.URLError, TimeoutError, ValueError):
                if attempt == 2:
                    raise
            pause(2)
        raise RuntimeError("App Store Connect retries exhausted")

    apps = fetch("/v1/apps", {"filter[bundleId]": bundle_id})
    if len(apps) != 1:
        raise RuntimeError("Expected exactly one App Store Connect app for the bundle ID")
    app_id = apps[0]["id"]
    params = {
        "filter[app]": app_id,
        "filter[version]": build_number,
        "filter[preReleaseVersion.version]": version,
        "sort": "-uploadedDate",
        "limit": 15,
    }
    end = clock() + deadline_seconds
    while clock() < end:
        builds = fetch("/v1/builds", params)

        for build in builds:
            attr = build.get("attributes", {})
            uploaded_raw = attr.get("uploadedDate")
            if not uploaded_raw:
                continue
            if attr.get("version") != build_number or parse_timestamp(uploaded_raw) < started_dt:
                continue
            prerelease = build.get("relationships", {}).get("preReleaseVersion", {}).get("data")
            if not prerelease or not prerelease.get("id"):
                continue
            details = fetch("/v1/preReleaseVersions", {"filter[app]": app_id, "filter[version]": version})
            if prerelease["id"] not in {item["id"] for item in details}:
                continue
            state = attr.get("processingState")
            print(f"App {app_id} build {build['id']} version {version} ({build_number}): {state}", flush=True)
            if state in {"VALID", "COMPLETE"}:
                return build["id"]
            if state in {"FAILED", "INVALID"}:
                raise RuntimeError("TestFlight processing failed: " + state)
        pause(interval)
    raise TimeoutError("Exact TestFlight build not processed before deadline")


def main():
    parser = argparse.ArgumentParser()
    for flag in ("key-path", "key-id", "issuer-id", "bundle-id", "version", "build-number", "started-at"):
        parser.add_argument("--" + flag, required=True)
    args = parser.parse_args()
    try:
        build_id = poll(args.key_path, args.key_id, args.issuer_id, args.bundle_id,
                        args.version, args.build_number, args.started_at)
    except Exception as error:
        # API responses or environment may contain sensitive data: report error class, not raw response body.
        print(f"Release poll failed: {type(error).__name__}", file=sys.stderr)
        raise SystemExit(1)
    print("Processed TestFlight build ID: " + build_id)
    evidence_path = os.environ.get("EVIDENCE_PATH")
    if evidence_path:
        with open(os.path.join(evidence_path, "processed-build.json"), "w") as output:
            json.dump({"app_id": args.bundle_id, "version": args.version,
                       "build_number": args.build_number, "build_id": build_id,
                       "status": "PROCESSED"}, output, indent=2)
            output.write("\n")


if __name__ == "__main__":
    main()
