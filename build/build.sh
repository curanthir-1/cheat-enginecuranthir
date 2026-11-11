#!/bin/bash
# Cross-builds Cheat Engine (64-bit and 32-bit) and its Lazarus based helper projects for Windows, on Linux.
# Run build/setup-toolchain.sh once first. Usage: build/build.sh [output.zip]
#
# The result is the "Cheat Engine/bin" folder: a portable Cheat Engine. It is also zipped (without debug symbols).
set -euo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
CE="$ROOT/Cheat Engine"
OUT=${1:-$ROOT/dist/CheatEngine-community.zip}
LOG=${LOG:-$ROOT/dist/logs}
mkdir -p "$LOG" "$(dirname "$OUT")"

cd "$CE"

build() { # $1 = project, $2 = cpu, $3 = os, $4 = build mode ('' = the default mode of the project)
  local name
  name=$(echo "$1-$2" | tr '/ ' '__')
  local args=(--os="$3" --cpu="$2" --ws=win32)
  if [ -n "$4" ]; then args+=(--build-mode="$4"); fi
  echo "--- $1 ($2${4:+, $4})"
  if ! lazbuild "${args[@]}" "$1" > "$LOG/$name.log" 2>&1; then
    grep -E "Error:|Fatal:" "$LOG/$name.log" | head -20 || true
    echo "BUILD FAILED: $1 ($2). See $LOG/$name.log"
    exit 1
  fi
}

# FPC 3.2.2 can crash on stale unit files after interface changes, so always start clean
# (only compiler output folders: folders named lib/unitbin that contain no files tracked by git)
find . -type d \( -name lib -o -name unitbin \) -not -path "./bin/*" -prune -print0 | while IFS= read -r -d '' d; do
  if [ -z "$(git ls-files -- "$d" | head -1)" ]; then
    rm -rf "$d"
  fi
done

build cheatengine.lpi           x86_64 win64 "Release 64-Bit"
build cheatengine.lpi           i386   win32 "Release 32-Bit"

build speedhack/speedhack.lpi   x86_64 win64 "64-bit"
build speedhack/speedhack.lpi   i386   win32 "32-bit"
build VEHDebug/vehdebug.lpi     x86_64 win64 "release 64"
build VEHDebug/vehdebug.lpi     i386   win32 "release 32"
build luaclient/luaclient.lpi   x86_64 win64 "Release 64"
build luaclient/luaclient.lpi   i386   win32 "Release 32"
build allochook/allochook.lpi   x86_64 win64 "64"
build allochook/allochook.lpi   i386   win32 "32"
build winhook/winhook.lpi       x86_64 win64 "Release 64"
build winhook/winhook.lpi       i386   win32 "Release 32"
build Tutorial/tutorial.lpi     x86_64 win64 ""
build Tutorial/tutorial.lpi     i386   win32 ""
build launcher/cheatengine.lpi  i386   win32 "release"
build ceregreset/ceregreset.lpi i386   win32 "Release"
build xmplayer/xmplayer.lpi     i386   win32 "Default"
build windowsrepair/windowsrepair.lpi x86_64 win64 "Release"
build cepack/cepack.lpi         x86_64 win64 "Default"

# lazbuild rewrites the project files (build counters, session data). Do not leave that in the working tree.
git -C "$ROOT" checkout -- '*.lpi' 2>/dev/null || true

# Cheat Engine starts the tutorials with a capital T
mv -f bin/tutorial-x86_64.exe bin/Tutorial-x86_64.exe
mv -f bin/tutorial-i386.exe bin/Tutorial-i386.exe

rm -f "$OUT"
(cd "$CE" && zip -q -r "$OUT" bin -x 'bin/*.dbg' -x 'bin/lib/*' -x 'bin/autorun/ceshare/server.txt')
echo "Done: $OUT ($(du -h "$OUT" | cut -f1))"
