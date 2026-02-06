#!/usr/bin/env bash

set -e

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# ─────────────────────────────────────────────────────────────
# Colors
# ─────────────────────────────────────────────────────────────
RESET="\033[0m"
BOLD="\033[1m"
GREEN="\033[32m"
YELLOW="\033[33m"
CYAN="\033[36m"
RED="\033[31m"

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

usage() {
  echo
  echo "Usage:"
  echo "add_dep.sh [-modules] [-packages] <package>"
  echo
  echo "Examples:"
  echo "add_dep.sh -modules pydantic"
  echo "add_dep.sh -packages httpx"
  echo "add_dep.sh -modules -packages fastapi"
  echo
  exit 1
}

# ─────────────────────────────────────────────────────────────
# Argument parsing
# ─────────────────────────────────────────────────────────────
ADD_MODULES=false
ADD_PACKAGES=false
PACKAGE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -modules)
      ADD_MODULES=true
      shift
      ;;
    -packages)
      ADD_PACKAGES=true
      shift
      ;;
    -*)
      error "Unknown option: $1"
      usage
      ;;
    *)
      PACKAGE="$1"
      shift
      ;;
  esac
done

if [[ -z "$PACKAGE" ]]; then
  error "Package name is required"
  usage
fi

if [[ "$ADD_MODULES" == "false" && "$ADD_PACKAGES" == "false" ]]; then
  error "At least one of -modules or -packages must be specified"
  usage
fi

echo
log "Adding dependency: ${BOLD}$PACKAGE${RESET}"
echo

cd "$ROOT_DIR"

# ─────────────────────────────────────────────────────────────
# Add to modules
# ─────────────────────────────────────────────────────────────
if [[ "$ADD_MODULES" == "true" ]]; then
  log "Processing modules"

  for dir in "$ROOT_DIR"/module-*; do
    [[ -d "$dir" ]] || continue

    if [[ -f "$dir/pyproject.toml" ]]; then
      log "module: $(basename "$dir")"
      (cd "$dir" && poetry add "$PACKAGE")
      success "Added to $(basename "$dir")"
    else
      warn "No pyproject.toml in $(basename "$dir")"
    fi

    echo
  done
fi

# ─────────────────────────────────────────────────────────────
# Add to packages
# ─────────────────────────────────────────────────────────────
if [[ "$ADD_PACKAGES" == "true" ]]; then
  log "Processing packages"

  for dir in "$ROOT_DIR"/package-*; do
    [[ -d "$dir" ]] || continue

    if [[ -f "$dir/pyproject.toml" ]]; then
      log "package: $(basename "$dir")"
      (cd "$dir" && poetry add "$PACKAGE")
      success "Added to $(basename "$dir")"
    else
      warn "No pyproject.toml in $(basename "$dir")"
    fi

    echo
  done
fi

success "Dependency addition completed 🚀"
