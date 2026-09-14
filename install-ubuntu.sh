#!/usr/bin/env bash
#
# install-ubuntu.sh — build the forked Remotely Save plugin and install it
# into a desktop Obsidian vault on Ubuntu.
#
# Usage:
#   ./install-ubuntu.sh --vault /path/to/vault [--no-build] [--android-bundle]
#
#   --vault PATH      Obsidian vault directory (required).
#   --no-build        Skip npm install / build, just copy existing main.js.
#   --android-bundle  Also produce remotely-save-android.zip for the phone.
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT=""
NO_BUILD=0
ANDROID_BUNDLE=0

usage() {
  sed -n '2,/^$/p' "$0"
  echo "Usage: $0 --vault /path/to/vault [--no-build] [--android-bundle]"
  exit "${1:-0}"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --vault) VAULT="${2:-}"; shift 2 ;;
    --no-build) NO_BUILD=1; shift ;;
    --android-bundle) ANDROID_BUNDLE=1; shift ;;
    -h|--help) usage 0 ;;
    *) echo "Unknown arg: $1" >&2; usage 1 ;;
  esac
done

[ -n "$VAULT" ] || { echo "ERROR: --vault is required." >&2; usage 1; }
[ -d "$VAULT" ] || { echo "ERROR: vault not found: $VAULT" >&2; exit 1; }

echo "==> Repo:   $REPO_DIR"
echo "==> Branch: $(git -C "$REPO_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo '?')"
echo "==> Commit: $(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo '?')"
echo "==> Vault:  $VAULT"

# 1. Node.js check (need >= 18 for the build toolchain).
if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  echo "ERROR: node and npm are required." >&2
  echo "Install with: sudo apt update && sudo apt install -y nodejs npm" >&2
  exit 1
fi
NODE_MAJOR="$(node --version | sed 's/^v\([0-9]*\).*/\1/')"
if [ "$NODE_MAJOR" -lt 18 ]; then
  echo "ERROR: node >= 18 required (found $(node --version))." >&2
  echo "See https://nodejs.org/en/download or use fnm/nvm." >&2
  exit 1
fi
echo "==> node $(node --version), npm $(npm --version)"

cd "$REPO_DIR"

# 2. .env with the public OAuth defaults (same values as the upstream
# release build; client IDs of installed apps are public by design).
if [ ! -f .env ]; then
  echo "==> Writing default .env (OneDrive public app credentials)"
  cat > .env <<'EOF'
# Public defaults, identical to the upstream release build.
# Needed only for the service you actually use.
ONEDRIVE_CLIENT_ID=3729fc1c-0af2-4bec-9376-d7ac4f0ff806
ONEDRIVE_AUTHORITY=https://login.microsoftonline.com/common
REMOTELYSAVE_WEBSITE=https://remotelysave.com
# Optional, see .env.example.txt for the full list:
# DROPBOX_APP_KEY=
# GOOGLEDRIVE_CLIENT_ID=
# GOOGLEDRIVE_CLIENT_SECRET=
EOF
else
  echo "==> Using existing .env"
fi

# 3. Dependencies + build.
if [ "$NO_BUILD" -eq 0 ]; then
  if [ ! -d node_modules ]; then
    echo "==> npm install (first run, takes a few minutes)"
    npm install --no-audit --no-fund
  fi
  echo "==> Building plugin (npm run build)"
  npm run build
else
  echo "==> Skipping build (--no-build)"
fi
[ -f main.js ] || { echo "ERROR: build did not produce main.js" >&2; exit 1; }

# 4. Sanity: the build must contain the OneDrive fix and the app ID.
grep -q "drive/special/approot:/" main.js \
  || { echo "ERROR: main.js lacks the OneDrive PATCH fix (wrong branch?)" >&2; exit 1; }
grep -q "3729fc1c-0af2-4bec-9376-d7ac4f0ff806" main.js \
  || { echo "ERROR: main.js lacks the OneDrive client ID (check .env)" >&2; exit 1; }
echo "==> Build sanity checks passed"

# 5. Install into the vault (never touches data.json with your tokens).
PLUGIN_DIR="$VAULT/.obsidian/plugins/remotely-save"
mkdir -p "$PLUGIN_DIR"
if [ -f "$PLUGIN_DIR/main.js" ]; then
  BACKUP="$PLUGIN_DIR/main.js.bak.$(date +%s)"
  echo "==> Backing up stock main.js to $(basename "$BACKUP")"
  cp "$PLUGIN_DIR/main.js" "$BACKUP"
fi
cp main.js manifest.json styles.css "$PLUGIN_DIR/"
echo "==> Installed to $PLUGIN_DIR"

# 6. Optional bundle for the Android phone.
if [ "$ANDROID_BUNDLE" -eq 1 ]; then
  BUNDLE_DIR="$REPO_DIR/remotely-save-android"
  rm -rf "$BUNDLE_DIR"
  mkdir -p "$BUNDLE_DIR"
  cp main.js manifest.json styles.css "$BUNDLE_DIR/"
  if command -v zip >/dev/null 2>&1; then
    (cd "$REPO_DIR" && rm -f remotely-save-android.zip && zip -q -j remotely-save-android.zip remotely-save-android/main.js remotely-save-android/manifest.json remotely-save-android/styles.css)
    echo "==> Android bundle: $REPO_DIR/remotely-save-android.zip"
  else
    echo "==> Android files (no 'zip' tool found, copy the folder as-is): $BUNDLE_DIR"
  fi
fi

cat <<'EOF'

Done. In Obsidian desktop:
  1. Settings -> Community plugins -> turn off Restricted mode (if needed).
  2. If Remotely Save was already enabled: disable + re-enable it
     (or Cmd/Ctrl+R) to load the new build.
  3. Open Remotely Save settings -> OneDrive -> Auth.

For the Android phone, run ./install-android.sh (or copy the android
bundle files by USB, see that script's instructions).
EOF
