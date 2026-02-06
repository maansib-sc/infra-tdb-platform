#!/usr/bin/env bash

set -e

COMMIT_MSG="${1:-sync}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ─────────────────────────────────────────────────────────────
# Colors
# ─────────────────────────────────────────────────────────────
RESET="\033[0m"
BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
RED="\033[31m"
CYAN="\033[36m"

log() {
  echo -e "${BOLD}${CYAN}▶ $1${RESET}"
}

success() {
  echo -e "${GREEN}✔ $1${RESET}"
}

warn() {
  echo -e "${YELLOW}⚠ $1${RESET}"
}

error() {
  echo -e "${RED}✖ $1${RESET}"
}

run_git_sync() {
  local dir="$1"
  local run_make_sync="$2"
  local run_poetry="$3"

  cd "$dir" || return

  log "Processing $(basename "$dir")"

  if [[ "$run_make_sync" == "true" ]]; then
    if make -q sync 2>/dev/null || make -n sync >/dev/null 2>&1; then
      log "Running make sync"
      make sync
    else
      warn "No 'sync' target in $(basename "$dir"), skipping"
    fi
  fi


  if [[ "$run_poetry" == "true" ]]; then
    log "Running poetry update"
    poetry update
  fi

  if [[ -n "$(git status --porcelain)" ]]; then
    log "Git changes detected, committing"
    git add .
    git commit -m "$COMMIT_MSG"
    git push
    success "Pushed $(basename "$dir")"
  else
    warn "No changes to commit in $(basename "$dir")"
  fi

  echo
}

echo -e "${BOLD}${BLUE}Root directory:${RESET} $ROOT_DIR"
echo

cd "$ROOT_DIR"

# ─────────────────────────────────────────────────────────────
# 1. base-tdb-models & base-tdb-clients (git only)
# ─────────────────────────────────────────────────────────────
if [[ -d "$ROOT_DIR/base-tdb-models" ]]; then
  run_git_sync "$ROOT_DIR/base-tdb-models" "false" "false"
fi

if [[ -d "$ROOT_DIR/base-tdb-clients" ]]; then
  run_git_sync "$ROOT_DIR/base-tdb-clients" "false" "false"
fi


# ─────────────────────────────────────────────────────────────
# 2. base-tdb-helpers (make sync + git)
# ─────────────────────────────────────────────────────────────
if [[ -d "$ROOT_DIR/base-tdb-helpers" ]]; then
  run_git_sync "$ROOT_DIR/base-tdb-helpers" "true" "false"
fi

# ─────────────────────────────────────────────────────────────
# 3. package-* (make sync + git)
# ─────────────────────────────────────────────────────────────
for dir in "$ROOT_DIR"/package-*; do
  [[ -d "$dir" ]] && run_git_sync "$dir" "true" "false"
done

# ─────────────────────────────────────────────────────────────
# 4. module-* (make sync + git)
# ─────────────────────────────────────────────────────────────
for dir in "$ROOT_DIR"/module-*; do
  [[ -d "$dir" ]] && run_git_sync "$dir" "true" "false"
done


success "All repositories processed successfully 🚀"
