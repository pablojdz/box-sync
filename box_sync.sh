#!/bin/bash
# Cloud backup: Documents and Downloads → Box
# ─────────────────────────────────────────────

set -euo pipefail

LOG="$HOME/.scripts/box-sync-log/box-sync.log"
mkdir -p "$(dirname "$LOG")"

# ── palette (Catppuccin Mocha) ────────────────
if [[ -t 1 ]]; then
  RST=$'\033[0m'
  BLD=$'\033[1m'
  DIM=$'\033[2m'
  GRN=$'\033[38;2;166;227;161m'   # green
  TEAL=$'\033[38;2;148;226;213m'  # teal
  SKY=$'\033[38;2;137;220;235m'   # sky
  SAP=$'\033[38;2;116;199;236m'  # sapphire
  BLU=$'\033[38;2;137;180;250m'   # blue
  MAU=$'\033[38;2;203;166;247m'   # mauve
  RED=$'\033[38;2;243;139;168m'   # red
  YLW=$'\033[38;2;249;226;175m'   # yellow
  PCH=$'\033[38;2;250;179;135m'   # peach
  TXT=$'\033[38;2;205;214;244m'   # text
  SUB=$'\033[38;2;166;173;200m'   # subtext0
  OVL=$'\033[38;2;108;112;134m'   # overlay0
  SUR=$'\033[38;2;88;91;112m'     # surface2
else
  RST= BLD= DIM= GRN= TEAL= SKY= SAP= BLU= MAU= RED= YLW= PCH= TXT= SUB= OVL= SUR=
fi

START_TS=$(date +%s)
START_HUMAN=$(date '+%Y-%m-%d %H:%M:%S')

log_file() {
  echo "=== $1: $(date '+%Y-%m-%d %H:%M:%S') ===" >> "$LOG"
}

rule() {
  printf "${SUR}%s${RST}\n" "────────────────────────────────────────────────────────"
}

banner() {
  rule
  printf "${GRN}${BLD}"
  printf "${RST}"
  printf "  ${OVL}::${RST} ${BLU}${BLD}FEDORA${RST} ${SUR}→${RST} ${MAU}${BLD}BOX CLOUD${RST} ${OVL}::${RST} ${PCH}rclone${RST}\n"
  printf "  ${SUB}session${RST} ${TXT}%s${RST}\n" "$START_HUMAN"
  rule
}

status_line() {
  local icon="$1" label="$2" state="$3" color="$4"
  printf "  ${color}${icon}${RST} ${BLD}%-12s${RST} ${SUR}│${RST} %s\n" "$label" "$state"
}

sync_target() {
  local name="$1" src="$2" remote="$3"
  local t0 t1 elapsed

  status_line "󰘿" "$name" "${SUB}syncing…${RST}" "$SAP"
  t0=$(date +%s)

  if rclone sync "$src" "$remote" \
    --progress \
    --log-file="$LOG" \
    --log-level INFO; then
    t1=$(date +%s)
    elapsed=$((t1 - t0))
    status_line "" "$name" "${GRN}OK${RST} ${SUB}(${elapsed}s)${RST}" "$GRN"
    return 0
  else
    status_line "󰅙" "$name" "${RED}FAILED${RST}" "$RED"
    return 1
  fi
}

footer() {
  local end elapsed mins secs
  end=$(date +%s)
  elapsed=$((end - START_TS))
  mins=$((elapsed / 60))
  secs=$((elapsed % 60))

  rule
  if [[ $FAILURES -eq 0 ]]; then
    printf "  ${GRN}${BLD}󰄬${RST} ${BLD}SYNC COMPLETE${RST}  ${SUR}│${RST}  ${TXT}%dm %02ds${RST}\n" "$mins" "$secs"
  else
    printf "  ${RED}${BLD}󰅙${RST} ${BLD}SYNC FINISHED WITH ERRORS${RST}  ${SUR}│${RST}  ${RED}%d failed${RST}  ${SUR}│${RST}  ${TXT}%dm %02ds${RST}\n" \
      "$FAILURES" "$mins" "$secs"
  fi
  printf "  ${SUB}log${RST} ${OVL}%s${RST}\n" "$LOG"
  rule
}

# ── main ──────────────────────────────────────
FAILURES=0

banner
log_file "Box Sync started"

sync_target "Documents" "$HOME/Documents" "box:Fedora/Documents" || ((FAILURES++)) || true
sync_target "Downloads"  "$HOME/Downloads"  "box:Fedora/Downloads"  || ((FAILURES++)) || true

footer
log_file "Box Sync finished"

exit "$FAILURES"
