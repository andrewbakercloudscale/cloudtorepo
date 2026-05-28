#!/usr/bin/env bash
# install.sh — set up a Python venv for sg-tightener.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
cd "$here"

if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 not found on PATH" >&2
  exit 1
fi

py_version=$(python3 -c 'import sys; print("%d.%d" % sys.version_info[:2])')
required="3.9"
if [ "$(printf '%s\n' "$required" "$py_version" | sort -V | head -n1)" != "$required" ]; then
  echo "Python $required or later is required (found $py_version)" >&2
  exit 1
fi

if [ ! -d .venv ]; then
  python3 -m venv .venv
fi

# shellcheck source=/dev/null
. .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt

cat <<'EOF'

sg-tightener installed.

To activate the venv in your current shell:
  source sg-tightener/.venv/bin/activate

Then run the tools, e.g.:
  python sg_tightener.py analyse --region us-east-1 --log-group <name>
  python sg_tightener.py plan    --region us-east-1 --approved approved.json
  python sg_tightener.py apply   --plan plan.json

Run the test suite at any time:
  python sg_tightener_test.py
EOF
