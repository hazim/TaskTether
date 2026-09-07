#!/usr/bin/env bash
#
# build-release.sh — build a distributable Release .app + .zip of TaskTether
# for direct sharing (owner + colleague). No notarisation, no App Store.
#
# Usage:
#   scripts/build-release.sh [--credentials <path>] [--team <TEAMID>] [--adhoc] [--out <dir>] [--no-dmg] [--no-pkg]
#
#   --credentials <path>  Copy this file in as GoogleCredentials.json inside
#                          the built app's Contents/Resources before signing.
#   --team <TEAMID>       Signing identity to use: the ID shown in parentheses
#                          by `security find-identity -v -p codesigning`.
#                          Required unless --adhoc is passed; may also be
#                          supplied via the DEVELOPMENT_TEAM env var.
#   --adhoc                Sign with the ad-hoc identity "-" instead of a
#                          team identity. Use on machines without the cert.
#   --out <dir>            Output directory for the zip and dmg (default: dist/).
#   --no-dmg               Skip building the drag-to-Applications .dmg (built
#                          by default alongside the .zip).
#   --no-pkg               Skip building the .pkg installer (built by default;
#                          its postinstall step launches the app right after
#                          install so it appears in the menu bar immediately).
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
CREDENTIALS=""
TEAM="${DEVELOPMENT_TEAM:-}"
ADHOC=0
OUT_DIR_ARG="dist"
DMG_ENABLED=1
PKG_ENABLED=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --credentials)
      CREDENTIALS="$2"; shift 2 ;;
    --team)
      TEAM="$2"; shift 2 ;;
    --adhoc)
      ADHOC=1; shift ;;
    --out)
      OUT_DIR_ARG="$2"; shift 2 ;;
    --no-dmg)
      DMG_ENABLED=0; shift ;;
    --no-pkg)
      PKG_ENABLED=0; shift ;;
    -h|--help)
      grep '^#' "$0" | sed 's/^#//'; exit 0 ;;
    *)
      echo "error: unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -n "$CREDENTIALS" && ! -f "$CREDENTIALS" ]]; then
  echo "error: --credentials file not found: $CREDENTIALS" >&2
  exit 1
fi

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ $ADHOC -eq 0 && -z "$TEAM" ]]; then
  echo "error: no signing team given. Pass --team <TEAMID> (or set DEVELOPMENT_TEAM)," >&2
  echo "       or use --adhoc to sign without a certificate. Available identities:" >&2
  security find-identity -v -p codesigning >&2 || true
  exit 1
fi

XCODEPROJ="$ROOT_DIR/TaskTether/TaskTether.xcodeproj"
ENTITLEMENTS="$ROOT_DIR/TaskTether/TaskTether/TaskTether.entitlements"

mkdir -p "$OUT_DIR_ARG"
OUT_DIR="$(cd "$OUT_DIR_ARG" && pwd)"
DERIVED_DATA="$OUT_DIR/.build/DerivedData"
rm -rf "$DERIVED_DATA"

echo "==> Project:      $XCODEPROJ"
echo "==> Entitlements:  $ENTITLEMENTS"
echo "==> Output dir:    $OUT_DIR"
echo "==> Mode:          $([[ $ADHOC -eq 1 ]] && echo "ad-hoc (identity: -)" || echo "team ($TEAM)")"

# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------
BUILD_ARGS=(
  -project "$XCODEPROJ"
  -scheme TaskTether
  -configuration Release
  -derivedDataPath "$DERIVED_DATA"
  build
  # Universal binary so the same zip runs on Intel and Apple Silicon Macs.
  ARCHS="arm64 x86_64"
  ONLY_ACTIVE_ARCH=NO
)

if [[ $ADHOC -eq 1 ]]; then
  BUILD_ARGS+=(
    CODE_SIGN_IDENTITY=-
    CODE_SIGN_STYLE=Manual
    DEVELOPMENT_TEAM=""
    ENABLE_HARDENED_RUNTIME=NO
  )
else
  # Manual signing with the locally installed certificate. Automatic signing
  # (CODE_SIGN_STYLE=Automatic + -allowProvisioningUpdates) requires Xcode to
  # log in to an Apple ID to refresh provisioning, which fails headlessly on
  # machines without an interactive signed-in account. Since a valid identity
  # for this team already lives in the keychain, sign with it directly.
  #
  # Passing the generic category name "Apple Development" to xcodebuild's
  # CODE_SIGN_IDENTITY fails ("No signing certificate 'Mac Development'
  # found") even when a matching cert exists — xcodebuild's manual-signing
  # resolution wants an exact identity. The SHA-1 hash always resolves.
  BUILD_IDENTITY_HASH="$(security find-identity -v -p codesigning | grep "$TEAM" | head -1 | awk '{print $2}')"
  if [[ -z "$BUILD_IDENTITY_HASH" ]]; then
    echo "error: no codesigning identity found for team $TEAM in keychain" >&2
    echo "       run: security find-identity -v -p codesigning" >&2
    exit 1
  fi
  BUILD_ARGS+=(
    DEVELOPMENT_TEAM="$TEAM"
    CODE_SIGN_STYLE=Manual
    CODE_SIGN_IDENTITY="$BUILD_IDENTITY_HASH"
    ENABLE_HARDENED_RUNTIME=YES
  )
fi


echo "==> Running: xcodebuild ${BUILD_ARGS[*]}"
xcodebuild "${BUILD_ARGS[@]}"

APP_PATH="$DERIVED_DATA/Build/Products/Release/TaskTether.app"
if [[ ! -d "$APP_PATH" ]]; then
  echo "error: build did not produce $APP_PATH" >&2
  exit 1
fi
echo "==> Built app: $APP_PATH"

# ---------------------------------------------------------------------------
# Optional: inject GoogleCredentials.json and re-sign
# ---------------------------------------------------------------------------
if [[ -n "$CREDENTIALS" ]]; then
  echo "==> Injecting credentials from $CREDENTIALS"
  cp "$CREDENTIALS" "$APP_PATH/Contents/Resources/GoogleCredentials.json"

  if [[ $ADHOC -eq 1 ]]; then
    IDENTITY="-"
    RESIGN_ARGS=(--force --deep --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" "$APP_PATH")
  else
    IDENTITY="$(security find-identity -v -p codesigning | grep "$TEAM" | head -1 | awk -F'"' '{print $2}')"
    if [[ -z "$IDENTITY" ]]; then
      echo "error: no codesigning identity found for team $TEAM in keychain" >&2
      echo "       run: security find-identity -v -p codesigning" >&2
      exit 1
    fi
    RESIGN_ARGS=(--force --deep --options runtime --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" "$APP_PATH")
  fi

  echo "==> Re-signing with identity: $IDENTITY"
  if ! codesign "${RESIGN_ARGS[@]}"; then
    if [[ $ADHOC -eq 0 ]]; then
      echo "==> Re-sign with hardened runtime failed, retrying without --options runtime"
      codesign --force --deep --sign "$IDENTITY" --entitlements "$ENTITLEMENTS" "$APP_PATH"
    else
      exit 1
    fi
  fi
fi

# ---------------------------------------------------------------------------
# Verification (fail loudly on real problems; spctl rejection is expected)
# ---------------------------------------------------------------------------
echo "==> Verifying signature (codesign --verify --deep --strict)"
if ! codesign --verify --deep --strict --verbose=2 "$APP_PATH"; then
  echo "error: codesign verification FAILED" >&2
  exit 1
fi
echo "==> Signature OK"

echo "==> codesign -dv --verbose=2 output:"
codesign -dv --verbose=2 "$APP_PATH" 2>&1 || true

echo "==> spctl --assess (expected to REJECT — app is not notarised):"
set +e
spctl --assess --type execute --verbose=2 "$APP_PATH" 2>&1
SPCTL_STATUS=$?
set -e
if [[ $SPCTL_STATUS -eq 0 ]]; then
  echo "==> NOTE: spctl accepted the app (unexpected but not a failure)."
else
  echo "==> spctl rejected as expected (not notarised, status=$SPCTL_STATUS)."
fi

# ---------------------------------------------------------------------------
# Package
# ---------------------------------------------------------------------------
VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_PATH/Contents/Info.plist")"
ZIP_NAME="TaskTether-${VERSION}.zip"
ZIP_PATH="$OUT_DIR/$ZIP_NAME"
rm -f "$ZIP_PATH"

echo "==> Packaging $ZIP_NAME"
ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

ZIP_SIZE="$(du -h "$ZIP_PATH" | cut -f1)"
ZIP_SHA="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"

# ---------------------------------------------------------------------------
# Package: DMG with classic drag-to-Applications window
# ---------------------------------------------------------------------------
make_dmg() {
  local dmg_name="TaskTether-${VERSION}.dmg"
  local dmg_path="$OUT_DIR/$dmg_name"
  local stage_dir="$OUT_DIR/.dmg-stage"
  local tmp_dmg="$OUT_DIR/.tmp-${VERSION}.dmg"

  echo "==> Checking for stale TaskTether mounts"
  local stale_mounts
  stale_mounts="$(hdiutil info | awk -F'\t' '{print $NF}' | grep -E '^/Volumes/TaskTether( [0-9]+)?$' || true)"
  if [[ -n "$stale_mounts" ]]; then
    while IFS= read -r stale_mount; do
      [[ -z "$stale_mount" ]] && continue
      echo "warn: detaching stale mount $stale_mount"
      hdiutil detach "$stale_mount" -force || true
    done <<< "$stale_mounts"
  fi

  echo "==> Staging DMG contents"
  rm -rf "$stage_dir"
  mkdir -p "$stage_dir"
  ditto "$APP_PATH" "$stage_dir/TaskTether.app"
  ln -s /Applications "$stage_dir/Applications"

  rm -f "$tmp_dmg" "$dmg_path"
  echo "==> Creating read-write DMG"
  hdiutil create -volname "TaskTether" -srcfolder "$stage_dir" -fs HFS+ -format UDRW -ov "$tmp_dmg"

  echo "==> Attaching DMG to lay out Finder window"
  local mount_output mount_point
  mount_output="$(hdiutil attach -readwrite -noverify -noautoopen "$tmp_dmg")"
  mount_point="$(echo "$mount_output" | grep -E '^/dev/' | awk -F'\t' '{print $NF}' | tail -1)"
  if [[ -z "$mount_point" ]]; then
    echo "error: failed to determine DMG mount point" >&2
    exit 1
  fi
  echo "==> Mounted at: $mount_point"
  local volume_name
  volume_name="$(basename "$mount_point")"

  if ! osascript <<EOF
tell application "Finder"
  tell disk "$volume_name"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {400, 100, 1000, 500}
    set theViewOptions to the icon view options of container window
    set arrangement of theViewOptions to not arranged
    set icon size of theViewOptions to 128
    set position of item "TaskTether.app" of container window to {160, 190}
    set position of item "Applications" of container window to {440, 190}
    close
    open
    update without registering applications
    delay 1
  end tell
end tell
EOF
  then
    echo "warn: Finder layout skipped"
  fi

  sync
  hdiutil detach "$mount_point" -force
  echo "==> Converting to compressed DMG"
  hdiutil convert "$tmp_dmg" -format UDZO -imagekey zlib-level=9 -o "$dmg_path"
  rm -f "$tmp_dmg"
  rm -rf "$stage_dir"

  echo "==> Signing DMG"
  local dmg_identity
  if [[ $ADHOC -eq 1 ]]; then
    dmg_identity="-"
  else
    dmg_identity="$(security find-identity -v -p codesigning | grep "$TEAM" | head -1 | awk -F'"' '{print $2}')"
  fi
  codesign --force --sign "$dmg_identity" "$dmg_path"
  echo "==> codesign -dv output:"
  codesign -dv "$dmg_path" 2>&1 || true

  DMG_PATH="$dmg_path"
  DMG_SIZE="$(du -h "$dmg_path" | cut -f1)"
  DMG_SHA="$(shasum -a 256 "$dmg_path" | awk '{print $1}')"
}

DMG_PATH=""
DMG_SIZE=""
DMG_SHA=""
if [[ $DMG_ENABLED -eq 1 ]]; then
  make_dmg
fi

# ---------------------------------------------------------------------------
# Package: .pkg installer that launches the app once installed
# ---------------------------------------------------------------------------
# Signing a .pkg needs a "Developer ID Installer" certificate, which the
# Apple Development identity used for the app does not include, so the
# package is left unsigned. Recipients right-click -> Open it once; the
# app it installs is not quarantined, so the app itself needs no such step.
make_pkg() {
  local pkg_name="TaskTether-${VERSION}.pkg"
  local pkg_path="$OUT_DIR/$pkg_name"
  local scripts_dir="$SCRIPT_DIR/pkg-scripts"

  rm -f "$pkg_path"
  echo "==> Building installer package $pkg_name"
  pkgbuild \
    --component "$APP_PATH" \
    --install-location /Applications \
    --scripts "$scripts_dir" \
    --identifier com.hazim.TaskTether \
    --version "$VERSION" \
    "$pkg_path"

  PKG_PATH="$pkg_path"
  PKG_SIZE="$(du -h "$pkg_path" | cut -f1)"
  PKG_SHA="$(shasum -a 256 "$pkg_path" | awk '{print $1}')"
}

PKG_PATH=""
PKG_SIZE=""
PKG_SHA=""
if [[ $PKG_ENABLED -eq 1 ]]; then
  make_pkg
fi

echo ""
echo "=================================================================="
echo " Build complete"
echo "=================================================================="
echo " Zip:    $ZIP_PATH"
echo " Size:   $ZIP_SIZE"
echo " SHA256: $ZIP_SHA"
if [[ -n "$DMG_PATH" ]]; then
  echo ""
  echo " Dmg:    $DMG_PATH"
  echo " Size:   $DMG_SIZE"
  echo " SHA256: $DMG_SHA"
fi
if [[ -n "$PKG_PATH" ]]; then
  echo ""
  echo " Pkg:    $PKG_PATH"
  echo " Size:   $PKG_SIZE"
  echo " SHA256: $PKG_SHA"
fi
echo ""
echo " Recipient instructions (.pkg — installs and starts the app):"
echo "   1. Right-click (or Control-click) TaskTether-${VERSION}.pkg and"
echo "      choose Open, then confirm — the package is not notarised."
echo "   2. Click through the installer (admin password required)."
echo "   3. TaskTether launches by itself and appears in the menu bar."
echo "      It registers itself to launch at login on first start."
echo ""
echo " Recipient instructions (.dmg — drag install, no admin password):"
echo "   1. Open TaskTether-${VERSION}.dmg"
echo "   2. Drag TaskTether.app onto the Applications shortcut"
echo "   3. Eject the TaskTether disk image"
echo "   4. First launch: right-click (or Control-click) TaskTether.app in"
echo "      /Applications and choose Open, then confirm in the Gatekeeper"
echo "      dialog — this app is not notarised, so a plain double-click"
echo "      will be blocked the first time."
echo "   5. TaskTether registers itself to launch at login on first start"
echo "      (macOS 13+); a toggle in Settings controls this."
echo "   6. If GoogleCredentials.json was not baked in, add it yourself:"
echo "      right-click TaskTether.app -> Show Package Contents ->"
echo "      Contents/Resources/ -> drop in GoogleCredentials.json."
echo ""
echo " Recipient instructions (.zip — alternative):"
echo "   1. Unzip TaskTether-${VERSION}.zip"
echo "   2. Move TaskTether.app to /Applications"
echo "   3. Follow steps 4-6 above."
echo "=================================================================="
