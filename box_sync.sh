#!/bin/bash
# Cloud backup: Documents and Downloads → Box
# ─────────────────────────────────────────────

set -euo pipefail

LOG="$HOME/.scripts/box-sync-log/box-sync.log"
FILTERS="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/rclone-filters.txt"
mkdir -p "$(dirname "$LOG")"

BAR_WIDTH=18
IS_TTY=0
[[ -t 1 ]] && IS_TTY=1

# ── palette (minimal Catppuccin) ──────────────
if (( IS_TTY )); then
  RST=$'\033[0m'
  BLD=$'\033[1m'
  ACC=$'\033[38;2;137;180;250m'   # blue
  MUT=$'\033[38;2;108;112;134m'   # overlay
  TXT=$'\033[38;2;205;214;244m'   # text
  OK=$'\033[38;2;166;227;161m'    # green
  ERR=$'\033[38;2;243;139;168m'   # red
else
  RST= BLD= ACC= MUT= TXT= OK= ERR=
fi

START_TS=$(date +%s)

# Target state: waiting | syncing | ok | fail
declare -a T_NAME=(Documents Downloads)
declare -a T_SRC=("$HOME/Documents" "$HOME/Downloads")
declare -a T_REMOTE=("box:Fedora/Documents" "box:Fedora/Downloads")
declare -a T_STATE=(waiting waiting)
declare -a T_ELAPSED=("" "")
declare -a T_RATIO=(0 0)
N_TARGETS=${#T_NAME[@]}
DASH_DRAWN=0
LAST_FRAME=""

cursor_hide() { (( IS_TTY )) && printf '\033[?25l'; }
cursor_show() { (( IS_TTY )) && printf '\033[?25h'; }
cleanup() { cursor_show; }
trap cleanup EXIT INT TERM

log_file() {
  echo "=== $1: $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$LOG"
}

# make_bar WIDTH RATIO -> smooth bar using fractional blocks
make_bar() {
  awk -v w="$1" -v r="$2" 'BEGIN {
    if (r < 0) r = 0; if (r > 1) r = 1;
    total = int(r * w * 8 + 0.5);
    full = int(total / 8); rem = total % 8;
    split("▏▎▍▌▋▊▉", p, "");
    s = ""; used = 0;
    for (i = 0; i < full; i++) { s = s "█"; used++ }
    if (rem > 0 && used < w) { s = s p[rem]; used++ }
    for (i = used; i < w; i++) s = s "░";
    printf "%s", s;
  }'
}

# eased, monotonic progress for the checking phase (no byte totals yet)
ease_ratio() {
  awk -v t="$1" 'BEGIN { r = 1 - exp(-t / 25.0); if (r > 0.92) r = 0.92; printf "%.4f", r }'
}

# read the latest byte-transfer percent rclone wrote to the log for this run.
# Prints the percent (0-100) when a real transfer is in progress, else nothing.
read_pct() {
  local off="$1"
  tail -n +"$((off + 1))" "$LOG" 2>/dev/null | awk '
    /Transferred:/ && /%/ {
      line = $0
      while (match(line, /[0-9]+%/)) {
        p = substr(line, RSTART, RLENGTH)
        line = substr(line, RSTART + RLENGTH)
      }
    }
    END { if (p != "") { sub(/%/, "", p); print p } }'
}

row_line() {
  local idx="$1"
  local name="${T_NAME[$idx]}"
  local state="${T_STATE[$idx]}"
  local elapsed="${T_ELAPSED[$idx]}"
  local mark bar_str status color

  case "$state" in
    waiting)
      mark="○"; color="$MUT"; status="waiting"
      bar_str=$(make_bar "$BAR_WIDTH" 0)
      ;;
    syncing)
      mark="●"; color="$ACC"; status="syncing"
      bar_str=$(make_bar "$BAR_WIDTH" "${T_RATIO[$idx]}")
      ;;
    ok)
      mark="✓"; color="$OK"; status="${elapsed}"
      bar_str=$(make_bar "$BAR_WIDTH" 1)
      ;;
    fail)
      mark="✗"; color="$ERR"; status="failed"
      bar_str=$(make_bar "$BAR_WIDTH" 1)
      ;;
  esac

  printf "  %s%s%s  %s%-11s%s  %s%s%s  %s%s%s" \
    "$color" "$mark" "$RST" \
    "$TXT" "$name" "$RST" \
    "$color" "$bar_str" "$RST" \
    "$MUT" "$status" "$RST"
}

banner() {
  printf "  %s%sbox%s  %s·%s  %sdocuments + downloads%s %s→%s %sfedora/box%s\n" \
    "$BLD" "$TXT" "$RST" "$MUT" "$RST" "$TXT" "$RST" "$MUT" "$RST" "$ACC" "$RST"
  printf "  %s%s%s\n\n" "$MUT" "$(date '+%-d %b %Y  %H:%M')" "$RST"
}

footer() {
  local end elapsed mins secs
  end=$(date +%s)
  elapsed=$((end - START_TS))
  mins=$((elapsed / 60))
  secs=$((elapsed % 60))

  printf "\n"
  if [[ $FAILURES -eq 0 ]]; then
    printf "  %sdone%s  %s·%s  %s%dm %02ds%s\n" "$OK" "$RST" "$MUT" "$RST" "$TXT" "$mins" "$secs" "$RST"
  else
    printf "  %sfailed%s  %s·%s  %s%d target(s)%s  %s·%s  %s%dm %02ds%s\n" \
      "$ERR" "$RST" "$MUT" "$RST" "$ERR" "$FAILURES" "$RST" "$MUT" "$RST" "$TXT" "$mins" "$secs" "$RST"
  fi
  printf "  %slog%s   %s·%s  %s%s%s\n" "$MUT" "$RST" "$MUT" "$RST" "$MUT" "$LOG" "$RST"
}

draw_dashboard() {
  local i frame=""
  for ((i = 0; i < N_TARGETS; i++)); do
    frame+="$(row_line "$i")"$'\n'
  done

  # Only repaint when something actually changed (kills flicker).
  if (( IS_TTY )) && [[ "$frame" == "$LAST_FRAME" ]]; then
    return
  fi
  LAST_FRAME="$frame"

  if (( IS_TTY )); then
    (( DASH_DRAWN )) && printf '\033[%dA' "$N_TARGETS"
    for ((i = 0; i < N_TARGETS; i++)); do
      printf '\r\033[K'
      row_line "$i"
      printf '\n'
    done
  fi
  DASH_DRAWN=1
}

run_rclone() {
  local src="$1" remote="$2"
  rclone sync "$src" "$remote" \
    --filter-from="$FILTERS" \
    --skip-links \
    --stats=1s \
    --stats-one-line \
    --log-file="$LOG" \
    --log-level INFO
}

sync_target() {
  local idx="$1"
  local t0 t1 rc log_off pct

  T_STATE[$idx]=syncing
  T_RATIO[$idx]=0
  t0=$(date +%s)
  log_off=$(wc -l < "$LOG" 2>/dev/null || echo 0)

  if (( ! IS_TTY )); then
    printf "  syncing %s...\n" "${T_NAME[$idx]}"
    if run_rclone "${T_SRC[$idx]}" "${T_REMOTE[$idx]}"; then
      t1=$(date +%s)
      T_STATE[$idx]=ok
      T_ELAPSED[$idx]="$((t1 - t0))s"
      printf "  ok %s (%s)\n" "${T_NAME[$idx]}" "${T_ELAPSED[$idx]}"
      return 0
    else
      T_STATE[$idx]=fail
      printf "  failed %s\n" "${T_NAME[$idx]}"
      return 1
    fi
  fi

  draw_dashboard

  run_rclone "${T_SRC[$idx]}" "${T_REMOTE[$idx]}" &
  local pid=$!

  while kill -0 "$pid" 2>/dev/null; do
    pct=$(read_pct "$log_off")
    if [[ -n "$pct" ]]; then
      # Real byte progress available (large upload in flight).
      T_RATIO[$idx]=$(awk -v p="$pct" 'BEGIN { printf "%.4f", p / 100 }')
    else
      # Checking phase / nothing to transfer: smooth time-based fill.
      T_RATIO[$idx]=$(ease_ratio "$(( $(date +%s) - t0 ))")
    fi
    draw_dashboard
    sleep 0.5
  done

  rc=0
  wait "$pid" || rc=$?

  t1=$(date +%s)
  if [[ $rc -eq 0 ]]; then
    T_STATE[$idx]=ok
    T_ELAPSED[$idx]="$((t1 - t0))s"
  else
    T_STATE[$idx]=fail
  fi
  draw_dashboard

  return "$rc"
}

# ── main ──────────────────────────────────────
FAILURES=0

banner
log_file "Box Sync started"

cursor_hide
if (( IS_TTY )); then
  draw_dashboard
fi

for ((i = 0; i < N_TARGETS; i++)); do
  sync_target "$i" || ((FAILURES++)) || true
done

footer
log_file "Box Sync finished"

exit "$FAILURES"
