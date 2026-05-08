#!/usr/bin/env bash

set -e

SYNC_MODE="${1:-git}"
PYTHON_BIN="${PYTHON_BIN:-python3.12}"

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

  # Fetch all remotes
  log "Fetching all remotes"
  git fetch --all --prune --quiet || warn "Fetch failed in $(basename "$dir"), continuing"

  # Pull latest changes (skips if detached / no upstream / dirty)
  if [[ -n "$(git status --porcelain)" ]]; then
    warn "Uncommitted changes in $(basename "$dir"), skipping pull"
  else
    local branch
    branch="$(git symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
    if [[ -z "$branch" ]]; then
      warn "Detached HEAD in $(basename "$dir"), skipping pull"
    elif ! git rev-parse --abbrev-ref "${branch}@{u}" >/dev/null 2>&1; then
      warn "No upstream for $branch in $(basename "$dir"), skipping pull"
    else
      log "Pulling latest on $branch"
      git pull --ff-only --quiet || warn "Pull failed in $(basename "$dir"), continuing"
    fi
  fi

  if [[ "$run_make_sync" == "true" ]]; then
    if make -q sync 2>/dev/null || make -n sync >/dev/null 2>&1; then
      log "Running make sync MODE=$SYNC_MODE"
      make sync MODE="$SYNC_MODE"
    else
      warn "No 'sync' target in $(basename "$dir"), skipping"
    fi
  fi


  if [[ "$run_poetry" == "true" ]]; then
    if command -v "$PYTHON_BIN" >/dev/null 2>&1; then
      poetry env use "$PYTHON_BIN" >/dev/null 2>&1 || warn "poetry env use $PYTHON_BIN failed in $(basename "$dir")"
    else
      warn "$PYTHON_BIN not found on PATH; poetry will auto-select an interpreter"
    fi

    if [[ "$SYNC_MODE" == "local" ]]; then
      log "Running poetry lock + install (local mode)"
      poetry lock || warn "Poetry lock failed in $(basename "$dir"), continuing"
      poetry install --no-root || warn "Poetry install failed in $(basename "$dir"), continuing"
    else
      log "Running poetry update"
      poetry update || warn "Poetry update failed in $(basename "$dir"), continuing"
    fi
  fi

  echo
}

echo -e "${BOLD}${BLUE}Root directory:${RESET} $ROOT_DIR"
echo -e "${BOLD}${BLUE}Sync mode:${RESET} $SYNC_MODE"
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
  run_git_sync "$ROOT_DIR/base-tdb-helpers" "true" "true"
fi

# ─────────────────────────────────────────────────────────────
# 3. package-* (make sync + git)
# ─────────────────────────────────────────────────────────────
for dir in "$ROOT_DIR"/package-*; do
  [[ -d "$dir" ]] && run_git_sync "$dir" "true" "true"
done

# ─────────────────────────────────────────────────────────────
# 4. module-* (make sync + git)
# ─────────────────────────────────────────────────────────────
for dir in "$ROOT_DIR"/module-*; do
  [[ -d "$dir" ]] && run_git_sync "$dir" "true" "true"
done


success "All repositories processed successfully 🚀"
