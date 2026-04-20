#!/usr/bin/env bash
set -euo pipefail

ROOT="/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml"
TOPIC="${NTFY_TOPIC_URL:-https://ntfy.sh/coyote-build-sdeheredia}"
MAIN_PID="${1:?usage: monitor_csynth_ntfy.sh <main-vitis-pid>}"
PROJECT_REL="${2:-artifacts/cnn_medium/hls/pytorch/fold_0}"
PROJECT_DIR="$ROOT/$PROJECT_REL"
PROJECT_NAME="$(awk '/set project_name/ {gsub(/"/, "", $3); print $3; exit}' "$PROJECT_DIR/project.tcl" 2>/dev/null || true)"
if [[ -z "$PROJECT_NAME" ]]; then
    PROJECT_NAME="cnn_medium_pytorch_hls"
fi
REPORT_DIR="$PROJECT_DIR/${PROJECT_NAME}_prj/solution1/syn/report"
VITIS_LOG="$PROJECT_DIR/vitis_hls.log"
SAFE_PROJECT="${PROJECT_REL//\//_}"
MONITOR_LOG="$ROOT/logs/${SAFE_PROJECT}_ntfy_monitor.log"
MESSAGE_FILE="$ROOT/logs/${SAFE_PROJECT}_ntfy_last_message.txt"

mkdir -p "$ROOT/logs"
start_ts="$(date -Is)"
echo "[$start_ts] monitoring PID $MAIN_PID project=$PROJECT_REL" >> "$MONITOR_LOG"

while kill -0 "$MAIN_PID" 2>/dev/null; do
    sleep 300
done

end_ts="$(date -Is)"
sleep 5

status="terminated"
if grep -q "C/RTL SYNTHESIS COMPLETED" "$VITIS_LOG" 2>/dev/null; then
    status="completed"
elif grep -q "ERROR:" "$VITIS_LOG" 2>/dev/null; then
    status="terminated_with_errors"
fi

report_list="$(find "$REPORT_DIR" -maxdepth 1 -type f -printf "%f %s bytes\n" 2>/dev/null | sort | sed -n "1,30p")"
last_log="$(tail -40 "$VITIS_LOG" 2>/dev/null || true)"

{
    printf "Coyote hls4ml fold_0 csynth %s\n" "$status"
    printf "start: %s\n" "$start_ts"
    printf "end: %s\n" "$end_ts"
    printf "main_pid: %s\n" "$MAIN_PID"
    printf "project: %s\n\n" "$PROJECT_REL"
    printf "reports:\n%s\n\n" "$report_list"
    printf "last log:\n%s\n" "$last_log"
} > "$MESSAGE_FILE"

if curl -fsS \
    -H "Title: Coyote csynth fold_0 $status" \
    -H "Tags: coyote,fpga,hls" \
    --data-binary "@$MESSAGE_FILE" \
    "$TOPIC" >> "$MONITOR_LOG" 2>&1; then
    echo "[$end_ts] ntfy sent: $status" >> "$MONITOR_LOG"
else
    echo "[$end_ts] ntfy failed: $status" >> "$MONITOR_LOG"
fi
