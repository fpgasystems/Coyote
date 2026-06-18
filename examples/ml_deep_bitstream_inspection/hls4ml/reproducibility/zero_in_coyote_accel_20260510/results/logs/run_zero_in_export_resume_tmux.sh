#!/usr/bin/env bash
set -euo pipefail

RUN_ROOT="/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/artifacts/coyote_accelerator_zero_in_e2e/20260509_173826"
BUILD_DIR="$RUN_ROOT/project/build/zero_in_coyote_accel_cyt_hw"
HLS_DIR="$BUILD_DIR/zero_in_coyote_accel_config_0/user_c0_0/hdl/ext/model_wrapper_hls"
TCL_SCRIPT="$HLS_DIR/resume_export_ip.tcl"
LOG_DIR="$RUN_ROOT/logs"
STAMP="$(date +%Y%m%d_%H%M%S)"
SESSION="zero_in_export_resume_${STAMP}"
MONITOR_SESSION="${SESSION}_monitor"
LOG="$LOG_DIR/${SESSION}.log"
STATUS="$LOG_DIR/${SESSION}.status"
PIDFILE="$LOG_DIR/${SESSION}.pid"
NTFY_TOPIC="coyote-build-sdeheredia"
VITIS_HLS_BIN="/tools/Xilinx/Vitis_HLS/2024.2/bin/vitis_hls"

mkdir -p "$LOG_DIR"

if [[ ! -f "$TCL_SCRIPT" ]]; then
  echo "missing Tcl script: $TCL_SCRIPT" >&2
  exit 1
fi

cat > "$LOG_DIR/${SESSION}.command.txt" <<CMD
cd "$HLS_DIR"
source /tools/Xilinx/Vivado/2024.2/settings64.sh
source /tools/Xilinx/Vitis/2024.2/settings64.sh
source /tools/Xilinx/Vitis_HLS/2024.2/settings64.sh
$VITIS_HLS_BIN -f "$TCL_SCRIPT"
CMD

tmux new-session -d -s "$SESSION" "bash -lc '
  set -uo pipefail
  echo running > \"$STATUS\"
  echo \"[start] \$(date -Is)\"
  echo \"[session] $SESSION\"
  echo \"[hls_dir] $HLS_DIR\"
  echo \"[tcl] $TCL_SCRIPT\"
  echo \"[log] $LOG\"
  echo \"[pid] \$$\"
  echo \$$ > \"$PIDFILE\"
  curl -s -d \"zero-in export STARTED session=$SESSION log=$LOG\" ntfy.sh/$NTFY_TOPIC >/dev/null || true
  source /tools/Xilinx/Vivado/2024.2/settings64.sh
  source /tools/Xilinx/Vitis/2024.2/settings64.sh
  source /tools/Xilinx/Vitis_HLS/2024.2/settings64.sh
  \"$VITIS_HLS_BIN\" -version
  cd \"$HLS_DIR\"
  \"$VITIS_HLS_BIN\" -f \"$TCL_SCRIPT\"
  rc=\$?
  echo \"[finish] \$(date -Is)\"
  echo \"[exit] \$rc\"
  if [[ \$rc -eq 0 ]]; then
    echo passed > \"$STATUS\"
    curl -s -d \"zero-in export PASSED session=$SESSION log=$LOG iprepo=$BUILD_DIR/iprepo/model_wrapper_hls_ip\" ntfy.sh/$NTFY_TOPIC >/dev/null || true
  else
    echo failed:\$rc > \"$STATUS\"
    curl -s -d \"zero-in export FAILED rc=\$rc session=$SESSION log=$LOG\" ntfy.sh/$NTFY_TOPIC >/dev/null || true
  fi
  exit \$rc
' > \"$LOG\" 2>&1"

tmux new-session -d -s "$MONITOR_SESSION" "bash -lc '
  set -uo pipefail
  while tmux has-session -t \"$SESSION\" 2>/dev/null; do
    sleep 300
  done
  status=\"unknown\"
  [[ -f \"$STATUS\" ]] && status=\$(cat \"$STATUS\")
  if [[ \"\$status\" == running ]]; then
    status=\"ended_without_status\"
    echo \"\$status\" > \"$STATUS\"
    curl -s -d \"zero-in export monitor: session ended without final status session=$SESSION log=$LOG\" ntfy.sh/$NTFY_TOPIC >/dev/null || true
  fi
'"

echo "started"
echo "session=$SESSION"
echo "monitor_session=$MONITOR_SESSION"
echo "log=$LOG"
echo "status=$STATUS"
echo "command=$LOG_DIR/${SESSION}.command.txt"
