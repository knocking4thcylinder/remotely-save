#!/usr/bin/env bash
#
# install-android.sh — get the forked Remotely Save plugin onto an Android
# phone. Two modes:
#
#   1. Automatic (needs USB debugging + adb on this Ubuntu machine):
#        ./install-android.sh --vault-device-path /sdcard/Obsidian/MyVault
#
#   2. Manual (no adb): builds remotely-save-android.zip (or uses the
#      folder) and prints USB copy instructions:
#        ./install-android.sh --manual
#
# The 3 plugin files (main.js, manifest.json, styles.css) must first exist
# in the repo root — run ./install-ubuntu.sh first.
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEVICE_VAULT=""
MANUAL=0

while [ $# -gt 0 ]; do
  case "$1" in
    --vault-device-path) DEVICE_VAULT="${2:-}"; shift 2 ;;
    --manual) MANUAL=1; shift ;;
    -h|--help) sed -n '2,/^$/p' "$0"; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 1 ;;
  esac
done

for f in main.js manifest.json styles.css; do
  [ -f "$REPO_DIR/$f" ] || {
    echo "ERROR: $REPO_DIR/$f missing. Run ./install-ubuntu.sh first." >&2
    exit 1
  }
done

if [ "$MANUAL" -eq 0 ] && command -v adb >/dev/null 2>&1 \
    && [ -n "$DEVICE_VAULT" ] && adb devices | grep -q "device$"; then
  echo "==> Pushing plugin to $DEVICE_VAULT via adb"
  adb shell "mkdir -p '$DEVICE_VAULT/.obsidian/plugins/remotely-save'"
  adb push "$REPO_DIR/main.js" \
    "$DEVICE_VAULT/.obsidian/plugins/remotely-save/main.js"
  adb push "$REPO_DIR/manifest.json" \
    "$DEVICE_VAULT/.obsidian/plugins/remotely-save/manifest.json"
  adb push "$REPO_DIR/styles.css" \
    "$DEVICE_VAULT/.obsidian/plugins/remotely-save/styles.css"
  echo "==> Done. On the phone: Obsidian -> Settings -> Community plugins"
  echo "    -> enable Remotely Save, then set up OneDrive -> Auth."
  exit 0
fi

# ---- Manual mode ----
BUNDLE_DIR="$REPO_DIR/remotely-save-android"
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR"
cp "$REPO_DIR/main.js" "$REPO_DIR/manifest.json" "$REPO_DIR/styles.css" "$BUNDLE_DIR/"
ZIP="$REPO_DIR/remotely-save-android.zip"
if command -v zip >/dev/null 2>&1; then
  (cd "$REPO_DIR" && rm -f remotely-save-android.zip \
    && zip -q -j remotely-save-android.zip \
      remotely-save-android/main.js \
      remotely-save-android/manifest.json \
      remotely-save-android/styles.css)
  echo "==> Bundle: $ZIP"
else
  echo "==> Files (no 'zip' tool; copy the folder contents): $BUNDLE_DIR"
fi

if [ "$MANUAL" -eq 0 ]; then
  echo "NOTE: automatic install unavailable." >&2
  if ! command -v adb >/dev/null 2>&1; then
    echo "  - adb not found (sudo apt install -y adb)." >&2
  elif [ -z "$DEVICE_VAULT" ]; then
    echo "  - pass --vault-device-path, e.g. --vault-device-path /sdcard/Obsidian/MyVault" >&2
  else
    echo "  - no authorized device (enable USB debugging, accept the RSA prompt)." >&2
  fi
  echo "Falling back to manual instructions:" >&2
fi

cat <<'EOF'

Manual Android install:
  1. Connect the phone by USB, choose "File transfer" mode.
  2. Copy main.js, manifest.json, styles.css into the vault folder:
       <vault>/.obsidian/plugins/remotely-save/
     (create the folders if missing; do NOT delete data.json if the
     plugin was already configured there.)
  3. On the phone: Obsidian -> Settings -> Community plugins ->
     turn off Restricted mode if asked -> enable Remotely Save.
  4. Remotely Save settings -> OneDrive -> Auth. Keep the vault name
     identical to desktop so both sync the same remote folder.
EOF
