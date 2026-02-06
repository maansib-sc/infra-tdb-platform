#!/usr/bin/env bash
set -e

CONFIG_DIR="$HOME/.tdbcli"
CONFIG_FILE="$CONFIG_DIR/config"

# Walk up from current directory to find the repo marker
find_repo_root() {
  local search_dir="$PWD"
  while [ "$search_dir" != "/" ]; do
    if [ -f "$search_dir/.tdbcli_root" ]; then
      echo "$search_dir"
      return 0
    fi
    search_dir="$(dirname "$search_dir")"
  done
  return 1
}

# 1) Highest priority: env var
if [ -n "${AW_REPO_ROOT:-}" ]; then
  REPO_ROOT="$AW_REPO_ROOT"
fi

# 2) Next: config file (if no env var)
if [ -z "${REPO_ROOT:-}" ] && [ -f "$CONFIG_FILE" ]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi

# 3) Next: auto-detect from current working directory (if still not found)
if [ -z "${REPO_ROOT:-}" ]; then
  if REPO_ROOT="$(find_repo_root)"; then
    :
  fi
fi

# 4) Auto-create config IF we now know REPO_ROOT and config doesn't exist
# (This is the missing piece in your current behavior)
if [ -n "${REPO_ROOT:-}" ] && [ ! -f "$CONFIG_FILE" ]; then
  mkdir -p "$CONFIG_DIR"
  printf "REPO_ROOT=%s\n" "$REPO_ROOT" > "$CONFIG_FILE"
  echo "✅ Auto-created config: $CONFIG_FILE"
fi

# Final check
if [ -z "${REPO_ROOT:-}" ]; then
  echo "❌ Error: Could not find repo root."
  echo "💡 Solutions:"
  echo "   1. Run from inside the repo (ensure .tdbcli_root exists in root)"
  echo "   2. Set AW_REPO_ROOT environment variable"
  echo "   3. Create $CONFIG_FILE with: REPO_ROOT=/path/to/repo"
  exit 1
fi

LOCAL_DIR="$REPO_ROOT/scripts"

usage() {
  echo "Usage: tdbcli {sync|deploy|add|rlog|cmd} [args...]"
  echo
  echo "Commands:"
  echo "  sync           Run scripts/sync_git.sh"
  echo "  deploy         Run scripts/deploy.sh"
  echo "  add            Run scripts/add_dep.sh"
  echo "  rlog           Run scripts/reset_logs.sh (sudo)"
  echo "  cmd            Run scripts/cmd_helper.sh"
}

if [ $# -lt 1 ]; then
  usage
  exit 0
fi

COMMAND=$1
shift

case "$COMMAND" in
  -h|--help|help)
    usage
    exit 0
    ;;
  sync)
    bash "$LOCAL_DIR/sync_git.sh" "$@"
    ;;
  deploy)
    bash "$LOCAL_DIR/deploy.sh" "$@"
    ;;
  add)
    bash "$LOCAL_DIR/add_dep.sh" "$@"
    ;;
  rlog)
    sudo bash "$LOCAL_DIR/reset_logs.sh" "$@"
    ;;
  cmd)
    bash "$LOCAL_DIR/cmd_helper.sh" "$@"
    ;;
  *)
    echo "Unknown command: $COMMAND"
    usage
    exit 1
    ;;
esac