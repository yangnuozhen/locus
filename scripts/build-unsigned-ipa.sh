#!/bin/bash
# Build a device app without signing; packaging does not require an Apple account.
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]] || ! command -v xcodebuild >/dev/null; then
  echo 'A Mac with full Xcode and an iOS SDK is required.' >&2
  exit 1
fi
if ! command -v xcodegen >/dev/null; then
  echo 'Install XcodeGen first: brew install xcodegen' >&2
  exit 1
fi
repo_dir="$PWD"
output_dir="${LOCUS_OUTPUT_DIR:-$repo_dir/outputs}"
mkdir -p "$output_dir"
output_dir="$(cd "$output_dir" && pwd)"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/locus-build.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT

# Verify the calculation layer and existing coordinate conversions before archiving.
xcrun swiftc -module-cache-path "$build_dir/module-cache" \
  Locus/Engine/MotionModel.swift Tests/MotionChecks.swift -o "$build_dir/motion-checks"
"$build_dir/motion-checks"
xcrun swiftc -module-cache-path "$build_dir/module-cache" \
  -D TUNNEL_CHECKS Locus/Engine/DeviceTunnel.swift Tests/TunnelChecks.swift -o "$build_dir/tunnel-checks"
"$build_dir/tunnel-checks"
xcrun swiftc -module-cache-path "$build_dir/module-cache" \
  Locus/Engine/CoordinateTransform.swift Tests/CoordinateTransformChecks.swift -o "$build_dir/coordinate-checks"
"$build_dir/coordinate-checks"

xcodegen generate
xcodebuild -project Locus.xcodeproj -scheme Locus -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$build_dir/Locus.xcarchive" \
  -derivedDataPath "$build_dir/DerivedData" \
  CODE_SIGNING_ALLOWED=NO archive 2>&1 | tee "$output_dir/build.log"

app_path="$build_dir/Locus.xcarchive/Products/Applications/Locus.app"
test -d "$app_path"
if codesign --verify "$app_path" >/dev/null 2>&1; then
  echo 'Expected an unsigned app, but signature verification succeeded.' >&2
  exit 1
fi
test ! -e "$app_path/_CodeSignature"
test ! -e "$app_path/embedded.mobileprovision"
mkdir -p "$build_dir/package/Payload"
cp -R "$app_path" "$build_dir/package/Payload/"
# zip from the parent to guarantee Payload/Locus.app is at the archive root.
(cd "$build_dir/package" && /usr/bin/zip -qr "$build_dir/Locus-unsigned.ipa" Payload)
unzip -t "$build_dir/Locus-unsigned.ipa"
mv "$build_dir/Locus-unsigned.ipa" "$output_dir/Locus-unsigned.ipa"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git rev-parse HEAD > "$output_dir/source-commit.txt"
  git status --short > "$output_dir/source-status.txt"
else
  echo 'Source archive: no Git revision metadata available' > "$output_dir/source-commit.txt"
  echo 'Source archive: working-tree status unavailable' > "$output_dir/source-status.txt"
fi
(cd "$output_dir" && shasum -a 256 Locus-unsigned.ipa > SHA256SUMS)
echo "Unsigned IPA: $output_dir/Locus-unsigned.ipa"
