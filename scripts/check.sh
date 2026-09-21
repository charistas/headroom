#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift test
bash scripts/build.sh
git diff --check

# A new repository has no tracked diff yet; check new text files as well.
while IFS= read -r -d '' file; do
    result=0
    git diff --no-index --check /dev/null "$file" || result=$?
    # --no-index returns 1 for a clean added file, 3 for whitespace errors.
    if [ "$result" -gt 1 ]; then exit "$result"; fi
done < <(git ls-files --others --exclude-standard -z)
