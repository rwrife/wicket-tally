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
  python3 - "$log_path" <<'PY'
import os
import re
import sys
from pathlib import Path

text = Path(sys.argv[1]).read_text(errors="replace")
for name in ("ASC_KEY_ID", "ASC_ISSUER_ID", "ASC_TEAM_ID", "ASC_KEY_PATH"):
    value = os.environ.get(name)
    if value:
        text = text.replace(value, "[REDACTED]")
text = re.sub(
    r"-----BEGIN [^-]*PRIVATE KEY-----.*?-----END [^-]*PRIVATE KEY-----",
    "[REDACTED PRIVATE KEY]",
    text,
    flags=re.DOTALL,
)
lines = text.splitlines()
print("\n".join(lines[-120:]), file=sys.stderr)
PY
  rm -f "$log_path"
  exit "$status"
fi

rm -f "$log_path"
