set -e

COMMIT_MSG="${1:-sync}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

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

push_repo() {
  local dir="$1"

  cd "$dir" || return

  log "Processing $(basename "$dir")"

  # Stage and commit any uncommitted changes
  if [[ -n "$(git status --porcelain)" ]]; then
    log "Git changes detected, committing"
    git add .
    git commit -m "$COMMIT_MSG"
    success "Committed $(basename "$dir")"
  fi

  # Push if there are unpushed commits
  local ahead
  ahead=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo "unknown")

  if [[ "$ahead" == "unknown" ]]; then
    warn "No upstream set for $(basename "$dir"), pushing with -u"
    git push -u origin "$(git branch --show-current)"
    success "Pushed $(basename "$dir")"
  elif [[ "$ahead" -gt 0 ]]; then
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

# ─────────────────────────────────────────────────────────────
# 1. base-tdb-models & base-tdb-clients
# ─────────────────────────────────────────────────────────────
if [[ -d "$ROOT_DIR/base-tdb-models" ]]; then
  push_repo "$ROOT_DIR/base-tdb-models"
fi

if [[ -d "$ROOT_DIR/base-tdb-clients" ]]; then
  push_repo "$ROOT_DIR/base-tdb-clients"
fi

# ─────────────────────────────────────────────────────────────
# 2. base-tdb-helpers
# ─────────────────────────────────────────────────────────────
if [[ -d "$ROOT_DIR/base-tdb-helpers" ]]; then
  push_repo "$ROOT_DIR/base-tdb-helpers"
fi

# ─────────────────────────────────────────────────────────────
# 3. package-*
# ─────────────────────────────────────────────────────────────
for dir in "$ROOT_DIR"/package-*; do
  [[ -d "$dir" ]] && push_repo "$dir"
done

# ─────────────────────────────────────────────────────────────
# 4. module-*
# ─────────────────────────────────────────────────────────────
for dir in "$ROOT_DIR"/module-*; do
  [[ -d "$dir" ]] && push_repo "$dir"
done

success "All repositories pushed successfully"
