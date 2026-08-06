#!/bin/bash
set -euo pipefail
# Every Swift file on disk must be registered in the Xcode project, or it
# silently never compiles (objectVersion 56 keeps explicit file lists).
missing=0
while IFS= read -r f; do
  base="$(basename "$f")"
  if ! grep -q "$base" Fiddle.xcodeproj/project.pbxproj; then
    echo "NOT IN TARGET: $f" >&2; missing=1
  fi
done < <(find Fiddle FiddleTests -name '*.swift')
exit $missing
