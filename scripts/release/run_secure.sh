#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 3 ] || [ "$2" != "--" ]; then
  echo "usage: $0 LOG_PATH -- COMMAND [ARG ...]" >&2
  exit 2
fi

log_path=$1
shift 2

set +e
"$@" >"$log_path" 2>&1
status=$?
set -e

if [ "$status" -ne 0 ]; then
  # ponytail: category-only diagnostics avoid leaking partial credentials; inspect raw logs only on the ephemeral runner.
  python3 - "$log_path" <<'PY'
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(errors="replace").lower()
categories = {
    "certificate-slot-limit": r"maximum number of certificates|choose a certificate to revoke",
    "provisioning-unavailable": r"no profiles for|provisioning profile",
    "authentication-rejected": r"unauthorized|authentication failed|invalid api key",
    "bundle-validation": r"missing required icon|invalid bundle|invalid binary",
    "upload-rejected": r"upload failed|unable to upload",
}
print("Secure command failed; exit status supplied by caller. Classified diagnostics only:", file=sys.stderr)
for label, pattern in categories.items():
    print(f"{label}: {len(re.findall(pattern, text))}", file=sys.stderr)
PY
  rm -f "$log_path"
  exit "$status"
fi

rm -f "$log_path"
