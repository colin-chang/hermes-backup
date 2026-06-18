#!/bin/bash
# Audit Homebrew third-party taps: cross-reference each tap's Formula/Casks
# against `brew list` to find which packages are actually installed.
#
# Usage: bash tap-audit.sh [tap1 tap2 ...]
#   With no args, audits all third-party taps from `brew tap`.

set -euo pipefail

TAPS="${@:-$(brew tap)}"

for tap in $TAPS; do
  tap_dir=$(brew --repo "$tap" 2>/dev/null) || continue
  [ ! -d "$tap_dir" ] && continue

  installed=()

  # Check Formula/ directory
  for f in "$tap_dir"/Formula/*.rb; do
    [ ! -f "$f" ] && continue
    name=$(basename "$f" .rb)
    brew list --formula "$name" &>/dev/null && installed+=("$name (Formula)")
  done

  # Check Casks/ directory
  for c in "$tap_dir"/Casks/*.rb; do
    [ ! -f "$c" ] && continue
    name=$(basename "$c" .rb)
    brew list --cask "$name" &>/dev/null && installed+=("$name (Cask)")
  done

  # Check root .rb files (some taps like yakitrak/yakitrak store formulae at root)
  for r in "$tap_dir"/*.rb; do
    [ ! -f "$r" ] && continue
    name=$(basename "$r" .rb)
    # Skip README.md etc that happen to end in .rb-like names
    [[ "$name" == "README" ]] && continue
    # Only check if not already counted from Formula/
    [ -f "$tap_dir/Formula/$name.rb" ] && continue
    brew list --formula "$name" &>/dev/null && installed+=("$name (Formula)")
  done

  if [ ${#installed[@]} -gt 0 ]; then
    echo "=== $tap ==="
    for item in "${installed[@]}"; do
      echo "  - $item"
    done
  else
    echo "=== $tap ===  (空 Tap — 无已安装包)"
  fi
  echo ""
done
