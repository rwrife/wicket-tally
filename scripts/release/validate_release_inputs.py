#!/usr/bin/env python3
import argparse
import re


SEMVER_PATTERN = re.compile(
    r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)"
)
BUILD_PATTERN = re.compile(r"[1-9][0-9]{0,17}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--tag", required=True)
    parser.add_argument("--marketing-version", required=True)
    parser.add_argument("--build-number", required=True)
    args = parser.parse_args()

    if not SEMVER_PATTERN.fullmatch(args.marketing_version):
        raise SystemExit(
            "FAIL: marketing version must be SemVer MAJOR.MINOR.PATCH without "
            "prerelease/build metadata"
        )
    if not BUILD_PATTERN.fullmatch(args.build_number):
        raise SystemExit(
            "FAIL: build number must be a positive integer with at most 18 digits"
        )

    expected_tag = (
        f"v{args.marketing_version}-rc.{args.build_number}"
    )
    if args.tag != expected_tag:
        raise SystemExit(
            f"FAIL: release-candidate tag must be {expected_tag!r}, got {args.tag!r}"
        )

    print(
        f"Release inputs: PASS ({args.marketing_version} "
        f"build {args.build_number}, tag {args.tag})"
    )


if __name__ == "__main__":
    main()
