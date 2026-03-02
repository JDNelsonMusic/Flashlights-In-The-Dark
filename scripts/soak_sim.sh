#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DURATION_SEC="${1:-${SIM_DURATION_SEC:-600}}"
CLIENTS="${SIM_CLIENTS:-28}"
LOSS_PCT="${SIM_LOSS_PCT:-2}"
JITTER_MS="${SIM_JITTER_MS:-30}"
DUPLICATION_PCT="${SIM_DUPLICATION_PCT:-3}"
REORDERING_PCT="${SIM_REORDERING_PCT:-3}"
MIN_ACK_RATIO="${SIM_MIN_ACK_RATIO:-0.97}"
MIN_CUES_PER_CLIENT="${SIM_MIN_CUES_PER_CLIENT:-1}"

printf 'Running concert soak simulation (%ss, %s clients)\n' "$DURATION_SEC" "$CLIENTS"

if python3 "$ROOT_DIR/tools/concert_sim.py" \
  --duration-sec "$DURATION_SEC" \
  --clients "$CLIENTS" \
  --loss-pct "$LOSS_PCT" \
  --jitter-ms "$JITTER_MS" \
  --duplication-pct "$DUPLICATION_PCT" \
  --reordering-pct "$REORDERING_PCT" \
  --min-ack-ratio "$MIN_ACK_RATIO" \
  --min-cues-per-client "$MIN_CUES_PER_CLIENT"; then
  echo 'SOAK RESULT: PASS'
else
  echo 'SOAK RESULT: FAIL'
  exit 1
fi
