#!/usr/bin/env bash
# Build, sign and install Claude Usage.app: a menu bar app with a
# Notification Center widget, carrying the Python collector inside it.
#
# Needs full Xcode with an Apple ID signed in (Xcode > Settings > Accounts;
# the free Personal Team is enough) and Python 3.10+ for bundling the
# collector.
#
#   macos/build.sh                      # auto-detects your team, installs to /Applications
#   TEAM_ID=ABCDE12345 macos/build.sh
#   INSTALL_DIR=~/Applications macos/build.sh
#   PYTHON=/path/to/python3 macos/build.sh
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
repo="$(dirname "$here")"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
install_dir="${INSTALL_DIR:-/Applications}"
build_dir="$here/build"
python="${PYTHON:-python3}"

if [[ -z "${TEAM_ID:-}" ]]; then
  # First team Xcode knows about (Settings > Accounts).
  TEAM_ID="$(defaults read com.apple.dt.Xcode IDEProvisioningTeamByIdentifier 2>/dev/null \
    | sed -n 's/.*teamID = \([A-Z0-9]*\);.*/\1/p' | head -1)"
fi
if [[ -z "$TEAM_ID" ]]; then
  echo "No signing team found. Sign in to Xcode > Settings > Accounts, or set TEAM_ID." >&2
  exit 1
fi
# Bundle IDs must be unique per Apple account; derive them from the team.
prefix="${BUNDLE_ID_PREFIX:-dev.claudeusage.$(tr '[:upper:]' '[:lower:]' <<<"$TEAM_ID")}"
mkdir -p "$build_dir"

# --- 1. Bundle the Python collector -----------------------------------------
echo "==> Bundling the Python collector"
venv="$build_dir/venv"
if [[ ! -x "$venv/bin/python" ]]; then
  "$python" -m venv "$venv"
  "$venv/bin/pip" install -q --upgrade pip
fi
"$venv/bin/pip" install -q pyinstaller "$repo"
# Reinstall the package itself every time so the bundle matches the working tree.
"$venv/bin/pip" install -q --force-reinstall --no-deps "$repo"
COLLECTOR_BUNDLE_ID="$prefix.ClaudeUsage.Collector" "$venv/bin/pyinstaller" \
  --noconfirm --log-level WARN \
  --distpath "$build_dir/collector-dist" \
  --workpath "$build_dir/collector-work" \
  "$here/collector/ClaudeUsageCollector.spec"
collector="$build_dir/collector-dist/ClaudeUsageCollector.app"

# --- 2. Build the Swift app and widget --------------------------------------
echo "==> Building the app with team $TEAM_ID, bundle prefix $prefix"
log="$build_dir/xcodebuild.log"
if ! xcodebuild \
  -project "$here/ClaudeUsage/ClaudeUsage.xcodeproj" \
  -scheme ClaudeUsage \
  -configuration Release \
  -derivedDataPath "$build_dir" \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  BUNDLE_ID_PREFIX="$prefix" \
  build >"$log" 2>&1; then
  grep -E "error:" "$log" | sort -u >&2 || true
  echo "Build failed. Full log: $log" >&2
  exit 1
fi
grep -E "warning:" "$log" | sort -u || true
app="$build_dir/Build/Products/Release/Claude Usage.app"

# --- 3. Embed the collector and re-sign ---------------------------------------
echo "==> Embedding the collector and signing"
# Sign with the same certificate Xcode just used for the app.
authority="$(codesign -dvv "$app" 2>&1 | sed -n 's/^Authority=\(Apple Development: .*\)$/\1/p' | head -1)"
identity="$(security find-identity -v -p codesigning | grep -F "\"$authority\"" | head -1 | awk '{print $2}')"
if [[ -z "$authority" || -z "$identity" ]]; then
  echo "Couldn't find the certificate Xcode signed the app with." >&2
  exit 1
fi
helpers="$app/Contents/Helpers"
rm -rf "$helpers"
mkdir -p "$helpers"
cp -R "$collector" "$helpers/"
# Inside out: the collector and everything in it, then the app around it.
# The widget extension keeps the signature Xcode gave it.
codesign --force --deep --options runtime --timestamp=none --sign "$identity" \
  "$helpers/ClaudeUsageCollector.app"
codesign --force --options runtime --timestamp=none --sign "$identity" \
  --entitlements "$here/ClaudeUsage/Config/App.entitlements" "$app"
codesign --verify --deep --strict "$app"

# --- 4. Install -------------------------------------------------------------
echo "==> Installing"
# The app quits cleanly on SIGTERM and stops the collector it started;
# the second pkill catches one left behind by a crash or an older build.
if pkill -TERM -x "Claude Usage" 2>/dev/null; then sleep 2; fi
pkill -TERM -f "Claude Usage.app/Contents/Helpers/ClaudeUsageCollector" 2>/dev/null || true
rm -rf "$install_dir/Claude Usage.app"
cp -R "$app" "$install_dir/"
open "$install_dir/Claude Usage.app"
echo "Installed $install_dir/Claude Usage.app ($(du -sh "$install_dir/Claude Usage.app" | cut -f1))"
