#!/bin/sh
set -euo pipefail

# Only run when archive produced dSYMs
if [ -z "${DWARF_DSYM_FOLDER_PATH:-}" ] || [ ! -d "${DWARF_DSYM_FOLDER_PATH}" ]; then
  echo "No dSYM folder; skipping Sentry upload."
  exit 0
fi

if ! command -v sentry-cli >/dev/null 2>&1; then
  echo "warning: sentry-cli not installed; skipping Sentry upload."
  exit 0
fi

# Prefer setting these in Xcode Cloud env vars (SENTRY_AUTH_TOKEN should be secret)
: "${SENTRY_ORG:?Missing SENTRY_ORG}"
: "${SENTRY_PROJECT:?Missing SENTRY_PROJECT}"
: "${SENTRY_AUTH_TOKEN:?Missing SENTRY_AUTH_TOKEN}"

sentry-cli debug-files upload --include-sources "$DWARF_DSYM_FOLDER_PATH"
