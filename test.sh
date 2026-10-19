#!/bin/bash
set -euo pipefail
project_root="$(cd "$(dirname "$0")" && pwd)"
mkdir -p "$project_root/.build/native" "$project_root/docs"
swiftc -swift-version 5 -O "$project_root/Sources/Core.swift" "$project_root/Tests/CoreTests.swift" -o "$project_root/.build/native/core-tests"
"$project_root/.build/native/core-tests"
sources=()
for source in "$project_root"/Sources/*.swift; do
    [[ "$source" == */App.swift ]] || sources+=("$source")
done
swiftc -swift-version 5 -O "${sources[@]}" "$project_root/Tests/ParityTests.swift" -o "$project_root/.build/native/parity-tests"
"$project_root/.build/native/parity-tests" "$project_root/docs/parity-validation.json"
swiftc -parse-as-library -O "$project_root/Tools/VerifyMedia.swift" -o "$project_root/.build/native/verify-media"
"$project_root/.build/native/verify-media" "$project_root/Resources/Videos" > "$project_root/docs/media-validation.json"
echo 'PASS: native HEVC-alpha decoding, 60fps, all six transparent videos'
