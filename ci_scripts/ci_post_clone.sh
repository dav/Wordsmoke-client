#!/bin/sh
set -euo pipefail

SENTRY_DOWNLOAD_URL="https://github.com/getsentry/sentry-cli/releases/latest/download/sentry-cli-Darwin-universal"

# Prefer Xcode Cloud repo path if available; otherwise use current directory
REPO_ROOT="${CI_PRIMARY_REPOSITORY_PATH:-${CI_WORKSPACE:-$(pwd)}}"

TOOLS_DIR="$REPO_ROOT/.tools"
mkdir -p "$TOOLS_DIR"

curl -sSL -o "$TOOLS_DIR/sentry-cli" "$SENTRY_DOWNLOAD_URL"
chmod +x "$TOOLS_DIR/sentry-cli"

echo "sentry-cli installed at: $TOOLS_DIR/sentry-cli"
"$TOOLS_DIR/sentry-cli" --version
