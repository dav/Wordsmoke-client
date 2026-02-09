#!/bin/sh
set -euo pipefail

SENTRY_DOWNLOAD_URL="https://github.com/getsentry/sentry-cli/releases/latest/download/sentry-cli-Darwin-universal"
TOOLS_DIR="$CI_WORKSPACE/.tools"
mkdir -p "$TOOLS_DIR"

# Download a macOS sentry-cli binary (adjust URL if you want to pin a version)
curl -sSL -o "$TOOLS_DIR/sentry-cli" "$SENTRY_DOWNLOAD_URL"

chmod +x "$TOOLS_DIR/sentry-cli"

# Make it available to later build steps (this matters)
export PATH="$TOOLS_DIR:$PATH"
echo "sentry-cli available at: $(which sentry-cli)"
sentry-cli --version
