#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
version=2.10.0
checksum=c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c
cache="$root/.build/sparkle"
if [[ -f "$cache/.verified-$checksum" && -d "$cache/Sparkle.framework" ]]; then exit 0; fi
mkdir -p "$root/.build"
archive="$root/.build/sparkle.tar.xz"
curl -fL --retry 3 "https://github.com/sparkle-project/Sparkle/releases/download/$version/Sparkle-$version.tar.xz" -o "$archive"
printf '%s  %s\n' "$checksum" "$archive" | shasum -a 256 -c -
mkdir -p "$cache"
tar -xf "$archive" -C "$cache"
touch "$cache/.verified-$checksum"
