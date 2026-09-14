#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
APP_PATH="$BUILD_DIR/SimSlim.app"
ICON_SOURCE="$ROOT_DIR/gui/Assets/AppIcon.png"
MACHINE_ARCH="$(uname -m)"
VERSION="${VERSION:-$(git -C "$ROOT_DIR" describe --tags --always --dirty)}"
APP_VERSION="${VERSION#v}"
APP_VERSION="${APP_VERSION%%-*}"
BUILD_NUMBER="${BUILD_NUMBER:-1}"

if ! print -r -- "$APP_VERSION" | grep -Eq '^[0-9]+(\.[0-9]+){0,2}$'; then
  APP_VERSION="0.0.0"
fi
if ! print -r -- "$BUILD_NUMBER" | grep -Eq '^[0-9]+(\.[0-9]+){0,2}$'; then
  echo "BUILD_NUMBER must contain one to three dot-separated integers." >&2
  exit 1
fi

if [[ "$(uname -s)" != "Darwin" ]]; then
  echo "The SimSlim app can only be built on macOS." >&2
  exit 1
fi

if ! command -v go >/dev/null 2>&1; then
  echo "Go is required. Install it with: brew install go" >&2
  exit 1
fi

if [[ ! -f "$ICON_SOURCE" ]]; then
  echo "App icon source is missing: $ICON_SOURCE" >&2
  exit 1
fi

# ARCHS selects the architectures bundled into SimSlim.app. It accepts one or
# more of arm64 / x86_64 separated by commas or spaces, `universal` as
# shorthand for both, and `all` for both plus one thin bundle per architecture
# (build/SimSlim-arm64.app, build/SimSlim-x86_64.app). Unset or empty builds
# only the build machine's architecture.
normalize_arch() {
  case "$1" in
    arm64|aarch64) print -r -- arm64 ;;
    x86_64|amd64|x64|i[3-6]86) print -r -- x86_64 ;;
    *) return 1 ;;
  esac
}

go_arch_for() {
  case "$1" in
    arm64) print -r -- arm64 ;;
    x86_64) print -r -- amd64 ;;
    *) return 1 ;;
  esac
}

SELECTED_ARCHS=()
PER_ARCH_BUNDLES=0
REQUESTED_ARCHS="${ARCHS:-$MACHINE_ARCH}"
REQUESTED_ARCHS="${REQUESTED_ARCHS//,/ }"
for token in ${=REQUESTED_ARCHS}; do
  case "$token" in
    universal|both) candidates=(arm64 x86_64) ;;
    all)
      candidates=(arm64 x86_64)
      PER_ARCH_BUNDLES=1
      ;;
    *)
      if ! candidate="$(normalize_arch "$token")"; then
        echo "Unsupported architecture: $token (supported: arm64, x86_64, universal, all)." >&2
        exit 1
      fi
      candidates=("$candidate")
      ;;
  esac
  for candidate in "${candidates[@]}"; do
    (( ${SELECTED_ARCHS[(I)$candidate]} )) || SELECTED_ARCHS+=("$candidate")
  done
done

if (( ${#SELECTED_ARCHS} == 0 )); then
  echo "ARCHS did not name any architecture. Use arm64, x86_64, universal, or all." >&2
  exit 1
fi

ARCHS_LABEL="${(j:, :)SELECTED_ARCHS}"
if (( ${#SELECTED_ARCHS} == 1 )); then
  echo "Target architecture: $ARCHS_LABEL"
else
  echo "Target architectures: $ARCHS_LABEL (universal)"
fi
if (( PER_ARCH_BUNDLES )) && (( ${#SELECTED_ARCHS} == 1 )); then
  echo "ARCHS=all needs more than one architecture; building $ARCHS_LABEL only." >&2
  PER_ARCH_BUNDLES=0
fi

# A per-architecture bundle carries exactly one slice, the one it is named for.
assert_single_arch() {
  local binary="$1" expected="$2" actual
  actual="$(lipo -archs "$binary")"
  if [[ "$actual" != "$expected" ]]; then
    echo "$binary has architecture '$actual'; expected '$expected'." >&2
    exit 1
  fi
}

# The CLI slot must hold the Go binary, not the SwiftUI app (they are easy to
# mix up while staging slices, and a swap builds a bundle that cannot run).
assert_go_cli() {
  local binary="$1"
  if ! otool -l "$binary" 2>/dev/null | grep -q __go_buildinfo; then
    echo "$binary is not the Go CLI; the app and CLI slices were mixed up." >&2
    exit 1
  fi
}

STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/simslim-app.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
STAGED_APP="$STAGING_DIR/SimSlim.app"

mkdir -p "$STAGED_APP/Contents/MacOS" "$STAGED_APP/Contents/Resources"
cp "$ROOT_DIR/gui/Info.plist" "$STAGED_APP/Contents/Info.plist"
plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$STAGED_APP/Contents/Info.plist"
plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$STAGED_APP/Contents/Info.plist"

# Bundle the in-app localization tables (gui/*.lproj) so language switching
# can load them from the app bundle at runtime.
for lproj_dir in "$ROOT_DIR"/gui/*.lproj; do
  [[ -d "$lproj_dir" ]] || continue
  lproj_name="$(basename "$lproj_dir")"
  mkdir -p "$STAGED_APP/Contents/Resources/$lproj_name"
  cp "$lproj_dir"/*.strings "$STAGED_APP/Contents/Resources/$lproj_name/"
done
if [[ -d "$STAGED_APP/Contents/Resources/zh-Hans.lproj" ]]; then
  plutil -replace CFBundleLocalizations -array "$STAGED_APP/Contents/Info.plist"
  plutil -insert CFBundleLocalizations.0 -string en "$STAGED_APP/Contents/Info.plist"
  plutil -insert CFBundleLocalizations.0 -string zh-Hans "$STAGED_APP/Contents/Info.plist"
fi

echo "Building macOS app icon…"
ICONSET_DIR="$STAGING_DIR/SimSlim.iconset"
mkdir -p "$ICONSET_DIR"
ICON_VARIANTS=(
  "16 icon_16x16.png"
  "32 icon_16x16@2x.png"
  "32 icon_32x32.png"
  "64 icon_32x32@2x.png"
  "128 icon_128x128.png"
  "256 icon_128x128@2x.png"
  "256 icon_256x256.png"
  "512 icon_256x256@2x.png"
  "512 icon_512x512.png"
  "1024 icon_512x512@2x.png"
)
for variant in "${ICON_VARIANTS[@]}"; do
  size="${variant%% *}"
  filename="${variant#* }"
  sips -s format png -z "$size" "$size" "$ICON_SOURCE" \
    --out "$ICONSET_DIR/$filename" >/dev/null
done
iconutil -c icns "$ICONSET_DIR" -o "$STAGED_APP/Contents/Resources/SimSlim.icns"

echo "Building bundled simslim CLI ($ARCHS_LABEL)…"
GO_SLICES=()
for arch in "${SELECTED_ARCHS[@]}"; do
  # Slices are named cli-*/app-*: on macOS's default case-insensitive
  # filesystem simslim-arm64 and SimSlim-arm64 would be the same file.
  slice="$STAGING_DIR/cli-$arch"
  (
    cd "$ROOT_DIR"
    CGO_ENABLED=0 GOOS=darwin GOARCH="$(go_arch_for "$arch")" \
      go build -trimpath -ldflags "-s -w -X main.version=$VERSION" \
      -o "$slice" ./cmd/simslim
  )
  GO_SLICES+=("$slice")
done
CLI_BINARY="$STAGED_APP/Contents/Resources/simslim"
if (( ${#GO_SLICES} == 1 )); then
  cp "${GO_SLICES[1]}" "$CLI_BINARY"
else
  lipo -create -output "$CLI_BINARY" "${GO_SLICES[@]}"
fi

echo "Building SwiftUI app ($ARCHS_LABEL)…"
SWIFT_SOURCES=(
  "$ROOT_DIR/gui/Models.swift"
  "$ROOT_DIR/gui/Backend.swift"
  "$ROOT_DIR/gui/Localization.swift"
  "$ROOT_DIR/gui/AppModel.swift"
  "$ROOT_DIR/gui/SimulatorManagementViews.swift"
  "$ROOT_DIR/gui/ContentView.swift"
  "$ROOT_DIR/gui/SimSlimApp.swift"
)
SWIFT_SLICES=()
for arch in "${SELECTED_ARCHS[@]}"; do
  slice="$STAGING_DIR/app-$arch"
  xcrun swiftc \
    -swift-version 5 \
    -warnings-as-errors \
    -parse-as-library \
    -O \
    -target "$arch-apple-macos14.0" \
    -module-name SimSlimApp \
    -framework AppKit \
    -framework SwiftUI \
    "${SWIFT_SOURCES[@]}" \
    -o "$slice"
  SWIFT_SLICES+=("$slice")
done

# `ARCHS=all` also emits a thin bundle per architecture beside the main one, so a
# single build hands out arch-specific downloads. Each starts as a copy of the
# skeleton (Info.plist, icon, localizations) and gets that architecture's slice.
if (( PER_ARCH_BUNDLES )); then
  echo "Assembling per-architecture bundles…"
  mkdir -p "$BUILD_DIR"
  for arch in "${SELECTED_ARCHS[@]}"; do
    ARCH_BUNDLE="$BUILD_DIR/SimSlim-$arch.app"
    rm -rf "$ARCH_BUNDLE"
    cp -R "$STAGED_APP" "$ARCH_BUNDLE"
    cp "$STAGING_DIR/cli-$arch" "$ARCH_BUNDLE/Contents/Resources/simslim"
    cp "$STAGING_DIR/app-$arch" "$ARCH_BUNDLE/Contents/MacOS/SimSlim"
    chmod +x "$ARCH_BUNDLE/Contents/MacOS/SimSlim" "$ARCH_BUNDLE/Contents/Resources/simslim"
    codesign --force --deep --sign - "$ARCH_BUNDLE" >/dev/null
    assert_single_arch "$ARCH_BUNDLE/Contents/MacOS/SimSlim" "$arch"
    assert_single_arch "$ARCH_BUNDLE/Contents/Resources/simslim" "$arch"
    assert_go_cli "$ARCH_BUNDLE/Contents/Resources/simslim"
    echo "Built $ARCH_BUNDLE ($arch)"
  done
fi

APP_BINARY="$STAGED_APP/Contents/MacOS/SimSlim"
if (( ${#SWIFT_SLICES} == 1 )); then
  cp "${SWIFT_SLICES[1]}" "$APP_BINARY"
else
  lipo -create -output "$APP_BINARY" "${SWIFT_SLICES[@]}"
fi

# Both bundled Mach-O binaries must carry exactly the requested slices, so a
# half-universal build fails loudly here instead of on an Intel Mac.
assert_archs() {
  local binary="$1" actual arch
  local -a found
  actual="$(lipo -archs "$binary")"
  found=(${=actual})
  if (( ${#found} != ${#SELECTED_ARCHS} )); then
    echo "$binary has ${#found} architecture(s) ($actual); expected ${#SELECTED_ARCHS} ($ARCHS_LABEL)." >&2
    exit 1
  fi
  for arch in "${SELECTED_ARCHS[@]}"; do
    if (( ! ${found[(I)$arch]} )); then
      echo "$binary is missing the $arch slice (found: $actual)." >&2
      exit 1
    fi
  done
}

chmod +x "$STAGED_APP/Contents/MacOS/SimSlim" "$STAGED_APP/Contents/Resources/simslim"
codesign --force --deep --sign - "$STAGED_APP" >/dev/null
assert_archs "$STAGED_APP/Contents/MacOS/SimSlim"
assert_archs "$STAGED_APP/Contents/Resources/simslim"
assert_go_cli "$STAGED_APP/Contents/Resources/simslim"

mkdir -p "$BUILD_DIR"
if [[ -e "$APP_PATH" ]]; then
  rm -rf "$APP_PATH"
fi
mv "$STAGED_APP" "$APP_PATH"

echo "Built $APP_PATH ($ARCHS_LABEL)"
