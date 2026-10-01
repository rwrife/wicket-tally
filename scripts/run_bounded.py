#!/usr/bin/env python3
"""Run a command with a wall-clock bound on macOS and keep its output."""
import subprocess
import sys

seconds, output, *command = sys.argv[1:]
with open(output, "w") as log:
    try:
        result = subprocess.run(command, stdout=log, stderr=subprocess.STDOUT,
                                timeout=int(seconds), check=False)
    except subprocess.TimeoutExpired:
        print(f"Timed out after {seconds}s: {' '.join(command)}", file=log)
        raise SystemExit(124)
raise SystemExit(result.returncode)
