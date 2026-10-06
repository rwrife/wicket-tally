#!/usr/bin/env python3
"""Generate an App Store Connect API JWT (ES256) using openssl CLI and Python stdlib."""
import base64
import json
import subprocess
import sys
import time


def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def der_to_raw_rs(der: bytes) -> bytes:
    """Convert ASN.1 DER ECDSA signature to 64-byte raw R || S."""
    if len(der) < 8 or der[0] != 0x30:
        raise ValueError("Invalid DER ECDSA signature format")
    # ASN.1 SEQUENCE length must cover exactly the two encoded integers.
    idx = 2
    if der[1] & 0x80:
        count = der[1] & 0x7F
        if count == 0 or count > 2 or idx + count > len(der):
            raise ValueError("Invalid DER sequence length")
        length = int.from_bytes(der[idx:idx + count], "big")
        idx += count
    else:
        length = der[1]
    if length != len(der) - idx:
        raise ValueError("DER sequence length mismatch")

    # First integer: R
    if der[idx] != 0x02:
        raise ValueError("Expected ASN.1 INTEGER for R")
    r_len = der[idx + 1]
    r_bytes = der[idx + 2: idx + 2 + r_len]
    idx = idx + 2 + r_len

    # Second integer: S
    if der[idx] != 0x02:
        raise ValueError("Expected ASN.1 INTEGER for S")
    s_len = der[idx + 1]
    s_bytes = der[idx + 2: idx + 2 + s_len]

    # Strip potential leading zero bytes from ASN.1 unsigned integers
    r_bytes = r_bytes.lstrip(b"\x00")
    s_bytes = s_bytes.lstrip(b"\x00")

    if len(r_bytes) > 32 or len(s_bytes) > 32:
        raise ValueError("ECDSA coordinate exceeds 32 bytes for P-256")

    # Left-pad to 32 bytes
    r_padded = r_bytes.rjust(32, b"\x00")
    s_padded = s_bytes.rjust(32, b"\x00")
    raw = r_padded + s_padded
    if len(raw) != 64:
        raise ValueError(f"Expected 64-byte raw signature, got {len(raw)}")
    return raw


def generate_jwt(key_path: str, key_id: str, issuer_id: str, exp_seconds: int = 1200) -> str:
    now = int(time.time())
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {
        "iss": issuer_id,
        "aud": "appstoreconnect-v1",
        "iat": now,
        "exp": now + exp_seconds,
    }
    header_b64 = b64url(json.dumps(header, separators=(",", ":")).encode("utf-8"))
    payload_b64 = b64url(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
    signing_input = f"{header_b64}.{payload_b64}".encode("ascii")

    res = subprocess.run(
        ["openssl", "dgst", "-binary", "-sha256", "-sign", key_path],
        input=signing_input,
        capture_output=True,
        check=True,
        timeout=15,
    )
    der_sig = res.stdout
    raw_sig = der_to_raw_rs(der_sig)
    sig_b64 = b64url(raw_sig)
    return f"{header_b64}.{payload_b64}.{sig_b64}"


def main():
    if len(sys.argv) != 4:
        print("usage: asc_jwt.py KEY_PATH KEY_ID ISSUER_ID", file=sys.stderr)
        raise SystemExit(2)
    key_path, key_id, issuer_id = sys.argv[1:4]
    try:
        token = generate_jwt(key_path, key_id, issuer_id)
        print(token)
    except Exception as exc:
        print(f"Failed to generate JWT: {type(exc).__name__}", file=sys.stderr)
        raise SystemExit(1)


if __name__ == "__main__":
    main()
