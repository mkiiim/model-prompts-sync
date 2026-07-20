#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SNAPSHOT_ROOT="${INSTRUCTION_SYNC_DIR:-$ROOT_DIR/.instruction-sync}"
MACHINES_FILE="${INSTRUCTION_MACHINES_FILE:-$ROOT_DIR/config/instruction-sync-machines.tsv}"

usage() {
  cat <<'USAGE'
Usage: bash scripts/instruction-sync.sh <command>

Commands:
  gather   Create a historical snapshot of live AGENTS.md and CLAUDE.md files from configured machines.
  diff     Compare the latest snapshot against repo AGENTS.md and CLAUDE.md.
  deploy   Copy repo AGENTS.md and CLAUDE.md to each configured machine.
  verify   Verify deployed machine files match repo AGENTS.md and CLAUDE.md.

Environment:
  INSTRUCTION_MACHINES_FILE="/path/to/instruction-sync-machines.tsv"
  INSTRUCTION_MACHINES="localhost host1 host2"  # legacy override, default paths
  INSTRUCTION_SYNC_DIR="/path/to/snapshots"
USAGE
}

machine_records() {
  if [ "${INSTRUCTION_MACHINES:-}" ]; then
    local machine
    for machine in $INSTRUCTION_MACHINES; do
      printf '%s|%s|~/.codex/AGENTS.md|~/.claude/CLAUDE.md\n' "$machine" "$machine"
    done
    return
  fi

  if [ ! -f "$MACHINES_FILE" ]; then
    printf 'Machine config not found: %s\n' "$MACHINES_FILE" >&2
    exit 1
  fi

  awk -F'|' '
    /^[[:space:]]*#/ || /^[[:space:]]*$/ { next }
    NF != 4 {
      printf "Invalid machine config line %d: expected 4 pipe-delimited fields\n", NR > "/dev/stderr"
      exit 1
    }
    {
      print $1 "|" $2 "|" $3 "|" $4
    }
  ' "$MACHINES_FILE"
}

is_local_machine() {
  case "$1" in
    localhost|127.0.0.1|"$(hostname)"|"$(hostname -s)") return 0 ;;
    *) return 1 ;;
  esac
}

is_local_target() {
  local machine="$1"
  local host="$2"

  if [ "$host" = "local" ]; then
    return 0
  fi

  is_local_machine "$machine" || is_local_machine "$host"
}

latest_snapshot() {
  if [ ! -d "$SNAPSHOT_ROOT" ]; then
    return 1
  fi

  find "$SNAPSHOT_ROOT" -mindepth 1 -maxdepth 1 -type d -print | sort | tail -n 1
}

copy_live_file() {
  local machine="$1"
  local host="$2"
  local source_path="$3"
  local target_path="$4"

  if is_local_target "$machine" "$host"; then
    local local_source_path="${source_path/#\~/$HOME}"
    if [ -f "$local_source_path" ]; then
      cp "$local_source_path" "$target_path"
    else
      printf 'missing: %s\n' "$local_source_path" > "$target_path.missing"
    fi
    return
  fi

  if ssh "$host" "test -f $source_path"; then
    ssh "$host" "cat $source_path" > "$target_path"
  else
    printf 'missing: %s:%s\n' "$host" "$source_path" > "$target_path.missing"
  fi
}

gather() {
  local snapshot_id
  local snapshot_dir

  snapshot_id="$(date -u +%Y%m%dT%H%M%SZ)"
  snapshot_dir="$SNAPSHOT_ROOT/$snapshot_id"
  mkdir -p "$snapshot_dir"

  {
    printf 'snapshot_id=%s\n' "$snapshot_id"
    printf 'created_utc=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    printf 'repo_root=%s\n' "$ROOT_DIR"
    printf 'repo_head=%s\n' "$(git -C "$ROOT_DIR" rev-parse --verify HEAD 2>/dev/null || printf 'unknown')"
    printf 'machine_config=%s\n' "$MACHINES_FILE"
    printf 'machine_records:\n'
    machine_records | sed 's/^/  /'
  } > "$snapshot_dir/_manifest.txt"

  while IFS='|' read -r machine host codex_path claude_path; do
    local machine_dir
    machine_dir="$snapshot_dir/$machine"
    mkdir -p "$machine_dir"

    copy_live_file "$machine" "$host" "$codex_path" "$machine_dir/AGENTS.md"
    copy_live_file "$machine" "$host" "$claude_path" "$machine_dir/CLAUDE.md"
  done < <(machine_records)

  printf '%s\n' "$snapshot_dir"
}

diff_snapshot() {
  local snapshot_dir
  snapshot_dir="${1:-}"
  if [ -z "$snapshot_dir" ]; then
    snapshot_dir="$(latest_snapshot || true)"
  fi

  if [ -z "$snapshot_dir" ] || [ ! -d "$snapshot_dir" ]; then
    printf 'No snapshot found. Run gather first.\n' >&2
    exit 1
  fi

  while IFS='|' read -r machine _host _codex_path _claude_path; do
    local machine_dir
    machine_dir="$snapshot_dir/$machine"

    if [ -f "$machine_dir/AGENTS.md" ]; then
      printf '\n## %s Codex diff\n' "$machine"
      diff -u "$ROOT_DIR/AGENTS.md" "$machine_dir/AGENTS.md" || true
    elif [ -f "$machine_dir/AGENTS.md.missing" ]; then
      printf '\n## %s Codex missing\n' "$machine"
      cat "$machine_dir/AGENTS.md.missing"
    fi

    if [ -f "$machine_dir/CLAUDE.md" ]; then
      printf '\n## %s Claude diff\n' "$machine"
      diff -u "$ROOT_DIR/CLAUDE.md" "$machine_dir/CLAUDE.md" || true
    elif [ -f "$machine_dir/CLAUDE.md.missing" ]; then
      printf '\n## %s Claude missing\n' "$machine"
      cat "$machine_dir/CLAUDE.md.missing"
    fi
  done < <(machine_records)
}

deploy_file() {
  local machine="$1"
  local host="$2"
  local source_file="$3"
  local target_file="$4"

  if is_local_target "$machine" "$host"; then
    local local_target_file="${target_file/#\~/$HOME}"
    mkdir -p "$(dirname "$local_target_file")"
    cp "$source_file" "$local_target_file"
    return
  fi

  ssh "$host" "mkdir -p \$(dirname $target_file)"
  scp "$source_file" "$host:$target_file"
}

deploy() {
  while IFS='|' read -r machine host codex_path claude_path; do
    deploy_file "$machine" "$host" "$ROOT_DIR/AGENTS.md" "$codex_path"
    deploy_file "$machine" "$host" "$ROOT_DIR/CLAUDE.md" "$claude_path"
    printf 'deployed: %s\n' "$machine"
  done < <(machine_records)
}

verify_file() {
  local machine="$1"
  local host="$2"
  local source_file="$3"
  local target_file="$4"
  local label="$5"

  if is_local_target "$machine" "$host"; then
    local local_target_file="${target_file/#\~/$HOME}"
    if cmp -s "$source_file" "$local_target_file"; then
      printf 'ok: %s %s\n' "$machine" "$label"
    else
      printf 'mismatch: %s %s\n' "$machine" "$label"
      return 1
    fi
    return
  fi

  if ssh "$host" "cmp -s - $target_file" < "$source_file"; then
    printf 'ok: %s %s\n' "$machine" "$label"
  else
    printf 'mismatch: %s %s\n' "$machine" "$label"
    return 1
  fi
}

verify() {
  local failed=0

  while IFS='|' read -r machine host codex_path claude_path; do
    verify_file "$machine" "$host" "$ROOT_DIR/AGENTS.md" "$codex_path" "Codex" || failed=1
    verify_file "$machine" "$host" "$ROOT_DIR/CLAUDE.md" "$claude_path" "Claude" || failed=1
  done < <(machine_records)

  return "$failed"
}

case "${1:-}" in
  gather) gather ;;
  diff) diff_snapshot "${2:-}" ;;
  deploy) deploy ;;
  verify) verify ;;
  -h|--help|help) usage ;;
  *)
    usage >&2
    exit 1
    ;;
esac
