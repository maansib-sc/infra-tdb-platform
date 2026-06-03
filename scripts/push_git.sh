#!/usr/bin/env bash

set -Eeuo pipefail

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

log()     { echo -e "${BOLD}${CYAN}▶ $1${RESET}"; }
success() { echo -e "${GREEN}✔ $1${RESET}"; }
warn()    { echo -e "${YELLOW}⚠ $1${RESET}"; }
error()   { echo -e "${RED}✖ $1${RESET}"; }

trap 'error "Failed at line $LINENO"' ERR

run_pre_sync() {
  local dir="$1"

  cd "$dir"

  if [[ -f "Makefile" ]] && grep -q "^sync:" Makefile; then
    log "Running make sync"
    make sync
  fi

  if [[ -f "pyproject.toml" ]] && command -v poetry >/dev/null 2>&1; then
    log "Running poetry update"
    poetry update
  fi
}

push_repo() {
  local dir="$1"

  cd "$dir"

  log "Processing $(basename "$dir")"

  # skip non-git dirs
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    warn "Not a git repo, skipping"
    return
  fi

  # run optional sync/update
  run_pre_sync "$dir"

  # commit if needed
  if [[ -n "$(git status --porcelain)" ]]; then
    log "Git changes detected, committing"
    git add .
    git commit -m "$COMMIT_MSG"
    success "Committed $(basename "$dir")"
  fi

  local branch
  branch="$(git branch --show-current)"

  # no upstream
  if ! git rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
    warn "No upstream set, pushing with -u"
    git push -u origin "$branch"
    success "Pushed $(basename "$dir")"
    echo
    return
  fi

  local ahead
  ahead="$(git rev-list --count @{u}..HEAD)"

  if (( ahead > 0 )); then
    log "$ahead commit(s) ahead, pushing"
    git push
    success "Pushed $(basename "$dir")"
  else
    warn "Nothing to push in $(basename "$dir")"
  fi

  echo
}

echo -e "${BOLD}${BLUE}Root directory:${RESET} $ROOT_DIR"
echo

cd "$ROOT_DIR"

# ordered explicit repos first
PRIORITY_REPOS=(
  "base-tdb-models"
  "base-tdb-clients"
  "base-tdb-helpers"
)

for repo in "${PRIORITY_REPOS[@]}"; do
  [[ -d "$ROOT_DIR/$repo" ]] && push_repo "$ROOT_DIR/$repo"
done

# all package-* repos
for dir in "$ROOT_DIR"/package-*; do
  [[ -d "$dir" ]] || continue
  push_repo "$dir"
done

# all module-* repos
for dir in "$ROOT_DIR"/module-*; do
  [[ -d "$dir" ]] || continue
  push_repo "$dir"
done

success "All repositories processed successfully 🚀"