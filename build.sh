#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")" && pwd)"
app_path="$project_root/dist/Pomolet.app"
build_path="$project_root/.build/native"
mkdir -p "$app_path/Contents/MacOS" "$app_path/Contents/Resources" "$build_path"
"$project_root/Tools/prepare-sparkle.sh"
mkdir -p "$app_path/Contents/Frameworks"
ditto "$project_root/.build/sparkle/Sparkle.framework" "$app_path/Contents/Frameworks/Sparkle.framework"
for clip in idle focus-adjust short short-eyes long long-yawn; do
    test -f "$project_root/Resources/Videos/$clip.mov" || { echo "Missing video: $clip.mov" >&2; exit 1; }
done
for arch in arm64 x86_64; do
    swiftc -F "$project_root/.build/sparkle" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks -swift-version 5 -O -target "$arch-apple-macos14.0" "$project_root"/Sources/*.swift -o "$build_path/Pomolet-$arch"
done
lipo -create "$build_path/Pomolet-arm64" "$build_path/Pomolet-x86_64" -output "$app_path/Contents/MacOS/Pomolet"
ditto "$project_root/Resources" "$app_path/Contents/Resources"
cp "$project_root/Info.plist" "$app_path/Contents/Info.plist"
codesign --force --deep --sign - --timestamp=none "$app_path"
codesign --verify --deep --strict "$app_path"
printf '%s\n' "$app_path"
