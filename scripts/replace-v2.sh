#!/bin/bash
# replace.sh — universal string replacement across files
# usage: ./replace.sh "old" "new" [file_or_dir] [--dry-run]

OLD="$1"
NEW="$2"
TARGET="${3:-.}"
DRY_RUN=0

# Parse flags
for arg in "$@"; do
  [[ "$arg" == "--dry-run" ]] && DRY_RUN=1
done

# Validate
if [[ -z "$OLD" || -z "$NEW" ]]; then
  echo "Usage: $0 'old_string' 'new_string' [file_or_dir] [--dry-run]"
  echo "  --dry-run   Show what would be changed without modifying files"
  exit 1
fi

COUNT=0

process_file() {
  local f="$1"
  if grep -q "$OLD" "$f" 2>/dev/null; then
    if [[ $DRY_RUN -eq 1 ]]; then
      echo "[dry-run] Would process: $f"
      grep -n "$OLD" "$f" | head -3
    else
      sed -i "s|$OLD|$NEW|g" "$f"
      echo "Processed: $f"
    fi
    ((COUNT++))
  fi
}

if [[ -f "$TARGET" ]]; then
  process_file "$TARGET"
else
  while IFS= read -r f; do
    process_file "$f"
  done < <(find "$TARGET" -type f 2>/dev/null)
fi

echo "---"
if [[ $DRY_RUN -eq 1 ]]; then
  echo "$COUNT file(s) would be modified"
else
  echo "$COUNT file(s) modified"
fi
