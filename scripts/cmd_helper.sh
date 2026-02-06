#!/usr/bin/env bash

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ─────────────────────────────────────────────────────────────
# Colors & logging
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

# ─────────────────────────────────────────────────────────────
# Ensure a command is provided
# ─────────────────────────────────────────────────────────────
if [[ $# -eq 0 ]]; then
  echo "Usage: $0 '<command>'"
  echo "Example: $0 'git checkout -b feature/document-models'"
  exit 1
fi

COMMAND="${*}"

# ─────────────────────────────────────────────────────────────
# Run command in a directory safely
# ─────────────────────────────────────────────────────────────
run_command() {
  local dir="$1"

  log "Processing $(basename "$dir")"

  # Run in a subshell so we don't affect the parent directory
  ( cd "$dir" && eval "$COMMAND" )
  local status=$?

  if [[ $status -ne 0 ]]; then
    warn "Command failed in $(basename "$dir"), moving to next"
  else
    success "Command finished in $(basename "$dir")"
  fi

  echo
}

# ─────────────────────────────────────────────────────────────
# Helper to loop over a pattern safely
# ─────────────────────────────────────────────────────────────
process_pattern() {
  local pattern="$1"
  shopt -s nullglob  # skip if no directories match
  for dir in "$ROOT_DIR"/$pattern; do
    [[ -d "$dir" ]] && run_command "$dir"
  done
  shopt -u nullglob
}

# ─────────────────────────────────────────────────────────────
# Root info
# ─────────────────────────────────────────────────────────────
echo -e "${BOLD}${BLUE}Root directory:${RESET} $ROOT_DIR"
echo

# ─────────────────────────────────────────────────────────────
# Process all directories
# ─────────────────────────────────────────────────────────────
process_pattern "base-*"
process_pattern "package-*"
process_pattern "module-*"

success "All directories processed ✅"
