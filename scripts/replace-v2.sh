#!/usr/bin/env bash
# replace.sh — literal string replacement across files
# usage: ./replace.sh "old" "new" [file_or_dir] [--dry-run]
#
# Strings are matched literally (no regex). .git/ is never touched.

set -uo pipefail

DRY_RUN=0
ARGS=()
for arg in "$@"; do
  if [[ "$arg" == "--dry-run" ]]; then DRY_RUN=1; else ARGS+=("$arg"); fi
done

OLD="${ARGS[0]:-}"
NEW="${ARGS[1]-}"
TARGET="${ARGS[2]:-.}"

if [[ -z "$OLD" || ${#ARGS[@]} -lt 2 ]]; then
  echo "Usage: $0 'old_string' 'new_string' [file_or_dir] [--dry-run]"
  echo "  --dry-run   Show what would be changed without modifying files"
  exit 1
fi

COUNT=0

process_file() {
  local f="$1"
  grep -Iq -F -- "$OLD" "$f" 2>/dev/null || return 0   # -I skips binary files
  if [[ $DRY_RUN -eq 1 ]]; then
    echo "[dry-run] Would process: $f"
    grep -n -F -- "$OLD" "$f" | head -3
  else
    OLD="$OLD" NEW="$NEW" perl -0pi -e 's/\Q$ENV{OLD}\E/$ENV{NEW}/g' "$f"
    echo "Processed: $f"
  fi
  COUNT=$((COUNT + 1))
}

if [[ -f "$TARGET" ]]; then
  process_file "$TARGET"
else
  while IFS= read -r -d '' f; do
    process_file "$f"
  done < <(find "$TARGET" -type d -name .git -prune -o -type f -print0 2>/dev/null)
fi

echo "---"
if [[ $DRY_RUN -eq 1 ]]; then
  echo "$COUNT file(s) would be modified"
else
  echo "$COUNT file(s) modified"
fi
