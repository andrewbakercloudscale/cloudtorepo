#!/usr/bin/env bash
# Install git hooks for local development.
# Run once after cloning: ./scripts/install-hooks.sh
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_DIR="${REPO_ROOT}/.git/hooks"
SCRIPTS_DIR="${REPO_ROOT}/scripts/hooks"

echo "Installing git hooks from ${SCRIPTS_DIR} → ${HOOKS_DIR}"

for hook in "${SCRIPTS_DIR}"/*; do
  name="$(basename "${hook}")"
  cp "${hook}" "${HOOKS_DIR}/${name}"
  chmod +x "${HOOKS_DIR}/${name}"
  echo "  installed: ${name}"
done

echo "Done. Hooks will run automatically on git commit/push."
