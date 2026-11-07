#!/usr/bin/env bash
# install.sh [--opencode] [--copy] [--zip]   (no args = --opencode --zip)
# --opencode  symlink ~/.config/opencode/skills/design-doc-lab-validation to this repo
#             (an existing real copy is moved to ~/.config/opencode/skill-backups/ first,
#             outside the skills dir so opencode does not load it twice)
# --copy      copy instead of symlink (if opencode does not follow symlinks)
# --zip       build dist/design-doc-lab-validation.zip for upload in Claude's skill settings
set -euo pipefail
ROOT=$(cd "$(dirname "$0")" && pwd); SK=design-doc-lab-validation
SKILLS=${OPENCODE_SKILLS:-$HOME/.config/opencode/skills}
BACKUPS=${SKILL_BACKUPS:-$HOME/.config/opencode/skill-backups}
OC=no; COPY=no; ZIP=no
[ $# -gt 0 ] || set -- --opencode --zip
for a in "$@"; do
  case "$a" in
    --opencode) OC=yes ;;
    --copy) OC=yes; COPY=yes ;;
    --zip) ZIP=yes ;;
    *) echo "usage: install.sh [--opencode] [--copy] [--zip]" >&2; exit 2 ;;
  esac
done
if [ "$OC" = yes ]; then
  DST=$SKILLS/$SK
  mkdir -p "$SKILLS"
  if [ -L "$DST" ]; then
    rm "$DST"
  elif [ -e "$DST" ]; then
    mkdir -p "$BACKUPS"; B=$BACKUPS/$SK-$(date -u +%Y%m%dT%H%M%SZ)
    mv "$DST" "$B"; echo "backed up previous copy to $B"
  fi
  if [ "$COPY" = yes ]; then
    if command -v rsync >/dev/null 2>&1; then
      rsync -a --exclude .DS_Store --exclude __pycache__ "$ROOT/$SK/" "$DST/"
    else
      cp -R "$ROOT/$SK" "$DST"
      find "$DST" \( -name .DS_Store -o -name __pycache__ \) -prune -exec rm -rf {} +
    fi
    echo "opencode: copied to $DST"
  else ln -s "$ROOT/$SK" "$DST"; echo "opencode: $DST -> $ROOT/$SK"; fi
fi
if [ "$ZIP" = yes ]; then
  mkdir -p "$ROOT/dist"; rm -f "$ROOT/dist/$SK.zip"
  (cd "$ROOT" && zip -qr "dist/$SK.zip" "$SK" -x '*.DS_Store' '*/__pycache__/*')
  echo "zip: $ROOT/dist/$SK.zip (upload it in Claude's skill settings; do not edit ~/.claude/skills/synced)"
fi
