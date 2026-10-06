#!/usr/bin/env python3
"""Synthetic API tests; these are not Apple signing or TestFlight evidence."""
import base64
import io
import json
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch

from poll_testflight import poll
from asc_jwt import generate_jwt
from validate_release_inputs import SEMVER_PATTERN, BUILD_PATTERN


class ReleaseTests(unittest.TestCase):
    def test_patterns(self):
        for value in ("0.1.0", "1.2.3"):
            self.assertTrue(SEMVER_PATTERN.fullmatch(value))
        for value in ("01.1.0", "v1.0.0", "1.0.0-rc.1"):
            self.assertFalse(SEMVER_PATTERN.fullmatch(value))
        for value in ("1", "42"):
            self.assertTrue(BUILD_PATTERN.fullmatch(value))
        for value in ("0", "-1", "1;exit"):
            self.assertFalse(BUILD_PATTERN.fullmatch(value))

    def test_jwt_es256_signature_is_raw_64_bytes(self):
        # Real openssl P-256 key: DER must be converted to raw R||S (skill pitfall:
        # raw DER bytes cause ASC HTTP 401 even when the key is valid).
        with tempfile.TemporaryDirectory() as directory:
            key_path = Path(directory, "test.p8")
            subprocess.run(["openssl", "ecparam", "-name", "prime256v1", "-genkey",
                            "-noout", "-out", str(key_path)], check=True,
                           capture_output=True)
            token = generate_jwt(str(key_path), "KEYID123", "issuer-abc")
            header_b64, payload_b64, signature_b64 = token.split(".")
            pad = lambda s: s + "=" * (-len(s) % 4)
            header = json.loads(base64.urlsafe_b64decode(pad(header_b64)))
            payload = json.loads(base64.urlsafe_b64decode(pad(payload_b64)))
            signature = base64.urlsafe_b64decode(pad(signature_b64))
            self.assertEqual(header, {"alg": "ES256", "kid": "KEYID123", "typ": "JWT"})
            self.assertEqual(payload["aud"], "appstoreconnect-v1")
            self.assertEqual(payload["iss"], "issuer-abc")
            self.assertGreater(payload["exp"], payload["iat"])
            self.assertLessEqual(payload["exp"] - payload["iat"], 1200)
            self.assertEqual(len(signature), 64)
            # A raw signature can also start with 0x30; its fixed length is the format proof.

    def run_poll(self, *, state="VALID", uploaded="2026-10-06T12:05:00Z",
                 number="42", release="0.1.0", relationship=True, apps=1):
        def request(req, timeout=30):
            from urllib.parse import parse_qs, urlparse
            url = urlparse(req.full_url)
            query = parse_qs(url.query)
            if url.path == "/v1/apps":
                self.assertEqual(query["filter[bundleId]"], ["com.infinityball.wickettally"])
                data = [{"id": f"app-{i}"} for i in range(apps)]
            elif url.path == "/v1/builds":
                data = [{"id": "build-999", "attributes": {
                    "version": number, "uploadedDate": uploaded, "processingState": state},
                    "relationships": {"preReleaseVersion": {"data": {"id": "pre-1"} if relationship else None}}}]
            else:
                self.assertEqual(query["filter[version]"], ["0.1.0"])
                data = [{"id": "pre-1", "attributes": {"version": release}}] if release == "0.1.0" else []
            return io.BytesIO(json.dumps({"data": data}).encode())

        now = [0]
        def clock():
            now[0] += 1
            return now[0]
        completed = subprocess.CompletedProcess(["ruby"], 0, stdout="synthetic-jwt", stderr="")
        with patch("subprocess.run", return_value=completed):
            return poll("synthetic-key", "KEY", "ISS", "com.infinityball.wickettally",
                        "0.1.0", "42", "2026-10-06T12:00:00Z", deadline_seconds=3,
                        interval=0, request=request, clock=clock, pause=lambda _: None)

    def test_exact_processed_build(self):
        self.assertEqual(self.run_poll(), "build-999")

    def test_reject_near_matches(self):
        with self.assertRaises(TimeoutError):
            self.run_poll(uploaded="2026-10-06T11:00:00Z")
        with self.assertRaises(TimeoutError):
            self.run_poll(number="41")
        with self.assertRaises(TimeoutError):
            self.run_poll(release="0.2.0")
        with self.assertRaises(TimeoutError):
            self.run_poll(relationship=False)
        with self.assertRaises(TimeoutError):
            self.run_poll(state="PROCESSING")

    def test_complete_state_accepted(self):
        self.assertEqual(self.run_poll(state="COMPLETE"), "build-999")

    def test_terminal_failure(self):
        for state in ("FAILED", "INVALID"):
            with self.subTest(state=state), self.assertRaises(RuntimeError):
                self.run_poll(state=state)

    def test_missing_or_ambiguous_app(self):
        for count in (0, 2):
            with self.subTest(count=count), self.assertRaises(RuntimeError):
                self.run_poll(apps=count)

    def test_secure_command_never_emits_raw_fragments(self):
        script = Path(__file__).with_name("run_secure.sh")
        with tempfile.TemporaryDirectory() as directory:
            log = Path(directory, "private.log")
            canary = "PRIVATE_FULL_SECRET_and_PARTIAL_abc123"
            result = subprocess.run(["bash", str(script), str(log), "--", "python3", "-c",
                                     f"print({canary!r}); print('No profiles for private.bundle'); raise SystemExit(7)"],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 7)
            self.assertNotIn(canary, result.stderr + result.stdout)
            self.assertNotIn("abc123", result.stderr + result.stdout)
            self.assertNotIn("private.bundle", result.stderr + result.stdout)
            self.assertIn("provisioning-unavailable: 1", result.stderr)
            self.assertFalse(log.exists())


if __name__ == "__main__":
    unittest.main()
