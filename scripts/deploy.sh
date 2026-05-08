#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Defaults (can be overridden by env)
LOCAL_SYNC="${LOCAL_SYNC:-0}"        # 1=run make sync if present
LOCAL_STRICT="${LOCAL_STRICT:-1}"    # 1=fail repos missing required targets, 0=skip them
LOCAL_SYNC_STRICT="${LOCAL_SYNC_STRICT:-0}"  # 1=sync failure fails that repo, 0=warn+continue

usage() {
  echo "Usage:"
  echo "  bash scriptsdeploy.sh up [--logs]"
  echo "  bash scriptsdeploy.sh down"
  echo "  bash scriptsdeploy.sh status"
  echo "  bash scriptsdeploy.sh logs"
  echo "  bash scriptsdeploy.sh local"
  echo "  bash scriptsdeploy.sh kill"
  echo ""
  echo "Repo Makefile contract:"
  echo "  required: dev down log"
  echo "  optional: sync ps"
  echo ""
  echo "Env:"
  echo "  LOCAL_SYNC=1|0"
  echo "  LOCAL_STRICT=1|0"
  echo "  LOCAL_SYNC_STRICT=1|0"
  exit 1
}

# ---------- colors ----------
is_tty() { [[ -t 1 ]]; }
if is_tty; then
  C_RESET=$'\033[0m'
  C_RED=$'\033[31m'
  C_GREEN=$'\033[32m'
  C_YELLOW=$'\033[33m'
  C_BLUE=$'\033[34m'
  C_DIM=$'\033[2m'
else
  C_RESET='' C_RED='' C_GREEN='' C_YELLOW='' C_BLUE='' C_DIM=''
fi

say() { echo -e "$*"; }
ok() { say "${C_GREEN}OK${C_RESET} $*"; }
warn() { say "${C_YELLOW}WARN${C_RESET} $*"; }
fail() { say "${C_RED}FAIL${C_RESET} $*"; }
info() { say "${C_BLUE}INFO${C_RESET} $*"; }
dim() { say "${C_DIM}$*${C_RESET}"; }

prefix_stream() {
  local name="$1"
  awk -v p="[$name] " '{ print p $0; fflush(); }'
}

list_packages() {
  for dir in "$ROOT_DIR"/package-*; do
    [[ -d "$dir" ]] || continue
    [[ -f "$dir/Makefile" ]] || continue
    echo "$dir"
  done
  for dir in "$ROOT_DIR"/module-*; do
    [[ -d "$dir" ]] || continue
    [[ -f "$dir/Makefile" ]] || continue
    echo "$dir"
  done
}

has_make_target() {
  local dir="$1" target="$2"
  [[ -f "$dir/Makefile" ]] || return 1
  grep -Eq "^[[:space:]]*${target}:" "$dir/Makefile"
}

preflight_repo() {
  local dir="$1"
  for t in dev down log; do
    if ! has_make_target "$dir" "$t"; then
      echo "missing target: $t"
      return 1
    fi
  done
  return 0
}

run_make() {
  local dir="$1" pkg="$2" target="$3"
  (
    cd "$dir"
    echo "[$(date '+%Y-%m-%dT%H:%M:%S')] make $target" | prefix_stream "$pkg"
    make "$target" 2>&1 | prefix_stream "$pkg"
  )
}

# Background log tail management (so Ctrl+C stops them)
LOG_PIDS=()
LOCAL_PIDS=()
cleanup_on_interrupt() {
  echo ""
  warn "Interrupted. Stopping local processes and log tails..."

  # Stop local make processes
  if [[ "${#LOCAL_PIDS[@]}" -gt 0 ]]; then
    for pid in "${LOCAL_PIDS[@]}"; do
      kill -TERM "$pid" >/dev/null 2>&1 || true
    done
    dim "Sent SIGTERM to local processes"
  fi

  # Stop log tails
  if [[ "${#LOG_PIDS[@]}" -gt 0 ]]; then
    for pid in "${LOG_PIDS[@]}"; do
      kill "$pid" >/dev/null 2>&1 || true
    done
    dim "Stopped log tails"
  fi

  dim "If services are still running, you can run: bash scriptsdeploy.sh down"
  exit 130
}


trap cleanup_on_interrupt INT

tail_all_logs_parallel() {
  info "Tailing logs for all packages (blocks). Ctrl+C to stop."
  for dir in "${PKG_DIRS[@]}"; do
    pkg="$(basename "$dir")"
    if has_make_target "$dir" "log"; then
      ( run_make "$dir" "$pkg" "log" ) &
      LOG_PIDS+=("$!")
    else
      warn "SKIP ${pkg}: missing target: log"
    fi
  done
  wait
}

list_package_dirs() {
  for dir in "$ROOT_DIR"/package-*; do
    [[ -d "$dir" && -f "$dir/Makefile" ]] && echo "$dir"
  done
}

list_module_dirs() {
  for dir in "$ROOT_DIR"/module-*; do
    [[ -d "$dir" && -f "$dir/Makefile" ]] && echo "$dir"
  done
}


cmd="${1:-}"
shift || true

WITH_LOGS=0
while [[ "${1:-}" != "" ]]; do
  case "$1" in
    --logs) WITH_LOGS=1; shift ;;
    *) usage ;;
  esac
done

case "$cmd" in
  up|down|status|logs|local|kill) ;;
  *) usage ;;
esac

kill_dev_processes() {
  local PATTERN="python -m debugpy.*uvicorn"
  local TIMEOUT=10

  info "Discovering running dev processes..."
  PIDS=()
  while IFS= read -r pid; do
    [[ -n "$pid" ]] && PIDS+=("$pid")
  done < <(ps -eo pid=,cmd= | grep "$PATTERN" | grep -v grep | awk '{print $1}')

  if [[ "${#PIDS[@]}" -eq 0 ]]; then
    ok "No matching dev processes found."
    return 0
  fi

  info "Sending SIGTERM to: ${PIDS[*]}"
  kill -TERM "${PIDS[@]}" 2>/dev/null || true

  for ((i=1; i<=TIMEOUT; i++)); do
    sleep 1
    STILL=()
    while IFS= read -r pid; do
      [[ -n "$pid" ]] && STILL+=("$pid")
    done < <(ps -p "${PIDS[@]}" -o pid= 2>/dev/null | xargs)

    if [[ "${#STILL[@]}" -eq 0 ]]; then
      ok "All dev processes exited gracefully."
      return 0
    fi

    dim "⏳ Waiting (${i}/${TIMEOUT}s): still running → ${STILL[*]}"
  done

  warn "Timeout reached. Force killing remaining processes..."
  kill -KILL "${STILL[@]}" 2>/dev/null || true
  ok "Force kill completed."
}

info "Root directory: $ROOT_DIR"
dim  "Mode: SEQUENTIAL start | LOCAL_SYNC=$LOCAL_SYNC | LOCAL_STRICT=$LOCAL_STRICT | LOCAL_SYNC_STRICT=$LOCAL_SYNC_STRICT"

PKG_DIRS=()
while IFS= read -r d; do
  [[ -n "$d" ]] && PKG_DIRS+=("$d")
done < <(list_packages)
TOTAL="${#PKG_DIRS[@]}"

if [[ "$cmd" == "up" ]]; then
  info "Starting packages..."

  started=0
  skipped=0
  failed=0
  idx=0

  for dir in "${PKG_DIRS[@]}"; do
    idx=$((idx+1))
    pkg="$(basename "$dir")"

    say ""
    info "[${idx}/${TOTAL}] ${pkg}"

    if msg="$(preflight_repo "$dir")"; then
      :
    else
      if [[ "$LOCAL_STRICT" == "1" ]]; then
        fail "FAIL ${pkg}: $msg"
        failed=$((failed+1))
        continue
      else
        warn "SKIP ${pkg}: $msg"
        skipped=$((skipped+1))
        continue
      fi
    fi

    # optional sync
    if [[ "$LOCAL_SYNC" == "1" ]] && has_make_target "$dir" "sync"; then
      if ! run_make "$dir" "$pkg" "sync"; then
        if [[ "$LOCAL_SYNC_STRICT" == "1" ]]; then
          fail "${pkg} sync failed"
          failed=$((failed+1))
          continue
        else
          warn "${pkg} sync failed (continuing)"
        fi
      fi
    fi

    # required dev
    if ! run_make "$dir" "$pkg" "dev"; then
      fail "${pkg} dev failed"
      failed=$((failed+1))
      continue
    fi

    # optional ps
    if has_make_target "$dir" "ps"; then
      run_make "$dir" "$pkg" "ps" || true
    fi

    ok "${pkg} started"
    started=$((started+1))
    dim "Progress: started=$started skipped=$skipped failed=$failed total=$TOTAL"
  done

  say ""
  info "Final summary:"
  dim "started=$started skipped=$skipped failed=$failed total=$TOTAL"

  if [[ "$failed" -gt 0 ]]; then
    fail "Some packages failed to start."
    exit 1
  fi

  if [[ "$WITH_LOGS" -eq 1 ]]; then
    tail_all_logs_parallel
  else
    ok "All started. Run: bash scriptsdeploy.sh logs  (to tail logs)"
  fi

  exit 0
fi

if [[ "$cmd" == "down" ]]; then
  info "Stopping packages..."
  idx=0
  for dir in "${PKG_DIRS[@]}"; do
    idx=$((idx+1))
    pkg="$(basename "$dir")"

    say ""
    info "[${idx}/${TOTAL}] ${pkg} (down)"

    if has_make_target "$dir" "down"; then
      run_make "$dir" "$pkg" "down" || fail "${pkg} down failed"
    else
      warn "SKIP ${pkg}: missing target: down"
    fi
  done
  ok "Done."
  exit 0
fi

if [[ "$cmd" == "status" ]]; then
  info "Status (best-effort):"
  for dir in "${PKG_DIRS[@]}"; do
    pkg="$(basename "$dir")"
    if has_make_target "$dir" "ps"; then
      run_make "$dir" "$pkg" "ps" || true
    else
      warn "SKIP ${pkg}: no ps target"
    fi
  done
  exit 0
fi

if [[ "$cmd" == "logs" ]]; then
  tail_all_logs_parallel
  exit 0
fi

if [[ "$cmd" == "local" ]]; then
  info "Running LOCAL mode (make local) in background..."

  FAILED=0

  start_local_group() {
    local label="$1"; shift
    local dirs=("$@")

    say ""
    info "Starting ${label} (background)..."

    for dir in "${dirs[@]}"; do
      pkg="$(basename "$dir")"

      if ! has_make_target "$dir" "local"; then
        if [[ "$LOCAL_STRICT" == "1" ]]; then
          fail "FAIL ${pkg}: missing target: local"
          FAILED=1
        else
          warn "SKIP ${pkg}: missing target: local"
        fi
        continue
      fi

      (
        run_make "$dir" "$pkg" "local"
      ) &
      LOCAL_PIDS+=("$!")
    done
  }

  PACKAGE_DIRS=()
  while IFS= read -r d; do
    [[ -n "$d" ]] && PACKAGE_DIRS+=("$d")
  done < <(list_package_dirs)

  MODULE_DIRS=()
  while IFS= read -r d; do
    [[ -n "$d" ]] && MODULE_DIRS+=("$d")
  done < <(list_module_dirs)

  # 1️⃣ Start packages
  start_local_group "packages" "${PACKAGE_DIRS[@]}"

  # 2️⃣ Small grace period so deps come up
  sleep 3

  # 3️⃣ Start modules
  start_local_group "modules" "${MODULE_DIRS[@]}"

  if [[ "$FAILED" -eq 1 ]]; then
    fail "One or more local targets were missing or failed to start."
    exit 1
  fi

  ok "Local services started. Streaming output (Ctrl+C to stop)..."
  wait "${LOCAL_PIDS[@]}"
  exit 0
fi

if [[ "$cmd" == "kill" ]]; then
  info "Force-stopping local dev services (graceful → hard)..."
  kill_dev_processes
  exit 0
fi
