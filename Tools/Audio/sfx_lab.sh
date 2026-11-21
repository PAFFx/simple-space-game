#!/usr/bin/env bash
# Runs sfx_lab.py in its uv environment (made on first run). See sfx_lab.py for commands.
set -euo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
exec uv run --quiet --project "$here" python -I "$here/sfx_lab.py" "$@"
