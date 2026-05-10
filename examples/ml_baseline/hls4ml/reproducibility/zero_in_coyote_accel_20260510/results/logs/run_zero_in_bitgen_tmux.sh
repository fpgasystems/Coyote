#!/usr/bin/env bash
set -euo pipefail

RUN_ROOT="/pub/scratch/sdeheredia/Coyote/examples/ml_baseline/hls4ml/artifacts/coyote_accelerator_zero_in_e2e/20260509_173826"
BUILD_DIR="$RUN_ROOT/project/build/zero_in_coyote_accel_cyt_hw"
LOG_DIR="$RUN_ROOT/logs"
STAMP="$(date +%Y%m%d_%H%M%S)"
SESSION="zero_in_bitgen_${STAMP}"
MONITOR_SESSION="${SESSION}_monitor"
LOG="$LOG_DIR/${SESSION}.log"
STATUS="$LOG_DIR/${SESSION}.status"
PIDFILE="$LOG_DIR/${SESSION}.pid"
NTFY_TOPIC="coyote-build-sdeheredia"

mkdir -p "$LOG_DIR"

cat > "$LOG_DIR/${SESSION}.command.txt" <<CMD
cd "$BUILD_DIR"
source /tools/Xilinx/Vivado/2024.2/settings64.sh
source /tools/Xilinx/Vitis/2024.2/settings64.sh
source /tools/Xilinx/Vitis_HLS/2024.2/settings64.sh
/tools/Xilinx/Vivado/2024.2/bin/vivado -mode tcl -source "$BUILD_DIR/cr_shell.tcl" -notrace
/tools/Xilinx/Vivado/2024.2/bin/vivado -mode tcl -source "$BUILD_DIR/cr_user.tcl" -notrace
make bitgen
CMD

tmux new-session -d -s "$SESSION" "bash -lc '
  set -uo pipefail
  echo running > \"$STATUS\"
  echo \"[start] \$(date -Is)\"
  echo \"[session] $SESSION\"
  echo \"[build_dir] $BUILD_DIR\"
  echo \"[log] $LOG\"
  echo \"[pid] \$$\"
  echo \$$ > \"$PIDFILE\"
  curl -s -d \"zero-in bitgen STARTED session=$SESSION log=$LOG\" ntfy.sh/$NTFY_TOPIC >/dev/null || true
  source /tools/Xilinx/Vivado/2024.2/settings64.sh
  source /tools/Xilinx/Vitis/2024.2/settings64.sh
  source /tools/Xilinx/Vitis_HLS/2024.2/settings64.sh
  which vivado
  which vitis_hls
  cd \"$BUILD_DIR\"

  echo \"[cr_shell] \$(date -Is)\"
  /tools/Xilinx/Vivado/2024.2/bin/vivado -mode tcl -source \"$BUILD_DIR/cr_shell.tcl\" -notrace
  rc=\$?
  if [[ \$rc -ne 0 ]]; then
    echo \"[exit] \$rc at cr_shell\"
    echo failed:\$rc > \"$STATUS\"
    curl -s -d \"zero-in bitgen FAILED rc=\$rc stage=cr_shell session=$SESSION log=$LOG\" ntfy.sh/$NTFY_TOPIC >/dev/null || true
    exit \$rc
  fi

  echo \"[cr_user] \$(date -Is)\"
  /tools/Xilinx/Vivado/2024.2/bin/vivado -mode tcl -source \"$BUILD_DIR/cr_user.tcl\" -notrace
  rc=\$?
  if [[ \$rc -ne 0 ]]; then
    echo \"[exit] \$rc at cr_user\"
    echo failed:\$rc > \"$STATUS\"
    curl -s -d \"zero-in bitgen FAILED rc=\$rc stage=cr_user session=$SESSION log=$LOG\" ntfy.sh/$NTFY_TOPIC >/dev/null || true
    exit \$rc
  fi

  echo \"[make_bitgen] \$(date -Is)\"
  make bitgen
  rc=\$?
  echo \"[finish] \$(date -Is)\"
  echo \"[exit] \$rc\"
  if [[ \$rc -eq 0 && -f \"$BUILD_DIR/bitstreams/cyt_top.bit\" ]]; then
    echo passed > \"$STATUS\"
    curl -s -d \"zero-in bitgen PASSED session=$SESSION bit=$BUILD_DIR/bitstreams/cyt_top.bit log=$LOG\" ntfy.sh/$NTFY_TOPIC >/dev/null || true
  else
    echo failed:\$rc > \"$STATUS\"
    curl -s -d \"zero-in bitgen FAILED rc=\$rc session=$SESSION log=$LOG\" ntfy.sh/$NTFY_TOPIC >/dev/null || true
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
    echo ended_without_status > \"$STATUS\"
    curl -s -d \"zero-in bitgen monitor: session ended without final status session=$SESSION log=$LOG\" ntfy.sh/$NTFY_TOPIC >/dev/null || true
  fi
'"

echo "started"
echo "session=$SESSION"
echo "monitor_session=$MONITOR_SESSION"
echo "log=$LOG"
echo "status=$STATUS"
echo "command=$LOG_DIR/${SESSION}.command.txt"
