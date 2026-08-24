#!/bin/zsh
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
app_dir="$project_dir/dist/StudyhCanvas.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"

rm -rf "$app_dir"
mkdir -p "$macos_dir" "$resources_dir"

xcrun swiftc \
  -target arm64-apple-macosx14.0 \
  "$project_dir"/StudyhCanvas/**/*.swift \
  -o "$macos_dir/StudyhCanvas"

cp "$project_dir/StudyhCanvas/Info.plist" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier tech.studyh.canvas" "$contents_dir/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleExecutable StudyhCanvas" "$contents_dir/Info.plist"

codesign --force --deep --sign - "$app_dir" >/dev/null
echo "Built $app_dir"
