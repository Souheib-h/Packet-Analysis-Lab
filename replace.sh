#!/bin/bash
# usage: ./replace.sh "old" "new" [file_or_pattern]
# si pas de fichier spécifié, cherche dans tout le répertoire courant

OLD="$1"
NEW="$2"
TARGET="${3:-.}" # défaut: répertoire courant

if [[ -z "$OLD" || -z "$NEW" ]]; then
  echo "Usage: $0 'old_string' 'new_string' [file_or_dir]"
  exit 1
fi

if [[ -f "$TARGET" ]]; then
  sed -i "s|$OLD|$NEW|g" "$TARGET"
  echo "Processed: $TARGET"
else
  find "$TARGET" -type f | while read -r f; do
    if grep -q "$OLD" "$f" 2>/dev/null; then
      sed -i "s|$OLD|$NEW|g" "$f"
      echo "Processed: $f"
    fi
  done
fi
