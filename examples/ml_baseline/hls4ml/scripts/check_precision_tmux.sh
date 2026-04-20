#!/usr/bin/env bash
set -euo pipefail

CANDIDATE="${CANDIDATE:-cnn_small_hls_opt_img512}"

echo "tmux sessions:"
tmux ls 2>/dev/null | grep "hls_${CANDIDATE}_" || true

echo
echo "run notes:"
find "artifacts/${CANDIDATE}/hls" -path "*/fold_0/run_note.txt" -print | sort | while read -r note; do
  echo "--- ${note}"
  grep -E '^(tag|default_precision|dense_precision|accum_precision|reuse_factor|sign_mismatches|project_dir|parity_dir)=' "$note" || true
done

echo
echo "csynth reports:"
find "artifacts/${CANDIDATE}/hls" -path "*/syn/report/*csynth.rpt" -print | sort || true

echo
echo "recent logs:"
ls -1t logs/csynth_${CANDIDATE}_*_fold0.log 2>/dev/null | head -20 || true
