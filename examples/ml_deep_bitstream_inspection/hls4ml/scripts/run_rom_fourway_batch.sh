#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

timestamp="$(date +%Y%m%d_%H%M%S)"
SESSION="${1:-hls4ml_rom_fourway_${timestamp}}"
OUT_ARG="${2:-artifacts/diagnostics/rom_fourway_${timestamp}}"
OUT="$(python - "$OUT_ARG" <<'PY'
from pathlib import Path
import sys
print(Path(sys.argv[1]).resolve())
PY
)"

if [[ -e "$OUT" ]]; then
    echo "Refusing to reuse existing output directory: $OUT" >&2
    exit 1
fi

mkdir -p "$OUT/logs" "$OUT/status" "$OUT/scripts"

cat > "$OUT/scripts/common.env" <<EOF
export ROOT="$ROOT"
export OUT="$OUT"
export LOGS="$OUT/logs"
export STATUS_DIR="$OUT/status"
export TOPIC="coyote-build-sdeheredia"
export PY="../.venv_hls4ml/bin/python"
export SRC_SWEEP="$ROOT/artifacts/diagnostics/rom_cnn_20260505_120214/rom_sample0_aclk100"
export SRC_RUN="$ROOT/artifacts/cnn_small_hls_opt_img256/notebook_qat/res256_layers5_W8A8_P0_RFbase_a7b3dc155907"
notify() { curl -s -d "\$*" "ntfy.sh/\$TOPIC" >/dev/null || true; }
EOF

cat > "$OUT/scripts/audit.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/common.env"
cd "$ROOT"
TRACK="audit"
LOG="$LOGS/${TRACK}.log"
STATUS="$STATUS_DIR/${TRACK}.status"
on_exit() {
    rc=$?
    status="passed"
    if [[ $rc -ne 0 ]]; then status="failed"; fi
    printf '%s rc=%s finished_at=%s log=%s\n' "$status" "$rc" "$(date --iso-8601=seconds)" "$LOG" > "$STATUS"
    notify "rom_fourway ${TRACK} ${status} rc=${rc} out=${OUT} log=${LOG}"
    exit "$rc"
}
trap on_exit EXIT
exec > >(tee -a "$LOG") 2>&1
echo "[$(date --iso-8601=seconds)] starting audit"
"$PY" - <<'PY' "$OUT"
from pathlib import Path
import json
import re
import sys

out = Path(sys.argv[1])
root = Path.cwd()
sample = root / "artifacts/diagnostics/rom_cnn_20260505_120214/rom_sample0_aclk100/fold_0/u55c_deployment"
zero = root / "artifacts/diagnostics/rom_cnn_20260505_120214/rom_zero_aclk100/fold_0/u55c_deployment"
rows = ["# ROM/Coyote Audit", ""]

for label, u55c in [("sample0", sample), ("zero", zero)]:
    rows += [f"## {label}", ""]
    manifest = u55c / "bitstream_manifest.json"
    if manifest.exists():
        data = json.loads(manifest.read_text())
        rows.append(f"- diagnostic: `{data.get('stage_fingerprint', {}).get('diagnostic')}`")
        rows.append(f"- build_failed: `{data.get('build_failed')}`")
        rows.append(f"- bitstream candidates: `{len(data.get('bitstream_candidates', []))}`")
    else:
        rows.append("- missing bitstream_manifest.json")

    vfpga = u55c / "coyote_hw/src/vfpga_top.svh"
    if vfpga.exists():
        text = vfpga.read_text(errors="ignore")
        reset_lines = [line.strip() for line in text.splitlines() if "ap_rst" in line or "aresetn" in line]
        rows.append(f"- vfpga_top.svh reset lines: `{'; '.join(reset_lines[:6])}`")
    else:
        rows.append("- missing vfpga_top.svh")

    ip = u55c / "coyote_hw/build_u55c/iprepo/coyote_qkeras_infer_hls_ip"
    component = ip / "component.xml"
    rtl = ip / "hdl/verilog/coyote_qkeras_infer.v"
    if component.exists():
        text = component.read_text(errors="ignore")
        polarity = re.findall(r"(?:POLARITY|POLARITY</spirit:name>).*?(ACTIVE_LOW|ACTIVE_HIGH)", text, re.S)
        rows.append(f"- component.xml reset polarity hits: `{polarity[:4]}`")
    else:
        rows.append("- missing component.xml")
    if rtl.exists():
        text = rtl.read_text(errors="ignore")
        ports = [line.strip() for line in text.splitlines() if "ap_rst" in line or "s_axi_in" in line or "m_axi_out" in line]
        rows.append(f"- generated RTL port/reset hits: `{'; '.join(ports[:10])}`")
    else:
        rows.append("- missing generated RTL")
    rows.append("")

(out / "audit.md").write_text("\n".join(rows) + "\n")
print(out / "audit.md")
PY
echo "[$(date --iso-8601=seconds)] audit complete"
EOF

cat > "$OUT/scripts/probe_task.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/common.env"
cd "$ROOT"
TRACK="$1"
CONFIG="$2"
RUN="$OUT/${TRACK}_run"
SWEEP="$OUT/${TRACK}"
U55C="$SWEEP/fold_0/u55c_deployment"
LOG="$LOGS/${TRACK}.log"
STATUS="$STATUS_DIR/${TRACK}.status"
on_exit() {
    rc=$?
    status="passed"
    if [[ $rc -ne 0 ]]; then status="failed"; fi
    printf '%s rc=%s finished_at=%s log=%s\n' "$status" "$rc" "$(date --iso-8601=seconds)" "$LOG" > "$STATUS"
    notify "rom_fourway ${TRACK} ${status} rc=${rc} out=${OUT} log=${LOG}"
    exit "$rc"
}
trap on_exit EXIT
exec > >(tee -a "$LOG") 2>&1

echo "[$(date --iso-8601=seconds)] starting ${TRACK}"
mkdir -p "$RUN" "$SWEEP/fold_0"
cp -a "$SRC_RUN/splits" "$RUN/splits"
cp -a "$SRC_SWEEP/fold_0/project" "$SWEEP/fold_0/project"
cp -a "$SRC_SWEEP/fold_0/parity" "$SWEEP/fold_0/parity"

echo "[$(date --iso-8601=seconds)] running bitstream stage"
./scripts/hls4ml_run.py \
  --config "$CONFIG" \
  --run-root "$RUN" \
  --hls-sweep-root "$SWEEP" \
  --stages bitstream \
  --force

echo "[$(date --iso-8601=seconds)] sourcing Vitis for wrapper C-sim"
export CLI_PATH=/opt/hdev/cli
export TERM="${TERM:-xterm}"
source /opt/hdev/cli/enable/vitis -v 2024.2

echo "[$(date --iso-8601=seconds)] running wrapper C-sim"
"$PY" scripts/test_u55c_wrapper_csim.py \
  --u55c-root "$U55C" \
  --work-dir "$OUT/${TRACK}_wrapper_csim" \
  --sample-index 0 \
  --max-samples 0

echo "[$(date --iso-8601=seconds)] running Coyote sim against wrapper C-sim expected lanes"
"$PY" scripts/run_coyote_sim_diagnostic.py \
  --u55c-root "$U55C" \
  --work-dir "$OUT/${TRACK}_coyote_sim" \
  --mode raw \
  --sample-index 0 \
  --expected-lanes-csv "$OUT/${TRACK}_wrapper_csim/wrapper_csim_results.csv" \
  --randomization both

echo "[$(date --iso-8601=seconds)] ${TRACK} complete"
EOF

cat > "$OUT/scripts/existing_coyote.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/common.env"
cd "$ROOT"
TRACK="existing_coyote"
LOG="$LOGS/${TRACK}.log"
STATUS="$STATUS_DIR/${TRACK}.status"
SAMPLE_U55C="$ROOT/artifacts/diagnostics/rom_cnn_20260505_120214/rom_sample0_aclk100/fold_0/u55c_deployment"
ZERO_U55C="$ROOT/artifacts/diagnostics/rom_cnn_20260505_120214/rom_zero_aclk100/fold_0/u55c_deployment"
on_exit() {
    rc=$?
    status="passed"
    if [[ $rc -ne 0 ]]; then status="failed"; fi
    printf '%s rc=%s finished_at=%s log=%s\n' "$status" "$rc" "$(date --iso-8601=seconds)" "$LOG" > "$STATUS"
    notify "rom_fourway ${TRACK} ${status} rc=${rc} out=${OUT} log=${LOG}"
    exit "$rc"
}
trap on_exit EXIT
exec > >(tee -a "$LOG") 2>&1

echo "[$(date --iso-8601=seconds)] starting existing ROM Coyote sims"
"$PY" scripts/run_coyote_sim_diagnostic.py \
  --u55c-root "$SAMPLE_U55C" \
  --work-dir "$OUT/existing_rom_sample0_coyote_sim" \
  --mode rom \
  --sample-index 0 \
  --expected-raw -2462 \
  --randomization both

"$PY" scripts/run_coyote_sim_diagnostic.py \
  --u55c-root "$ZERO_U55C" \
  --work-dir "$OUT/existing_rom_zero_coyote_sim" \
  --mode rom \
  --sample-index 0 \
  --expected-raw 4778 \
  --zero-stream-input \
  --randomization both

echo "[$(date --iso-8601=seconds)] existing ROM Coyote sims complete"
EOF

cat > "$OUT/scripts/status.sh" <<'EOF'
#!/usr/bin/env bash
set -Eeuo pipefail
source "$(dirname "$0")/common.env"
sent_overall=0
tracks=(audit rom_control_probe rom_layer_probe existing_coyote)
while true; do
    clear || true
    echo "rom_fourway status"
    echo "out: $OUT"
    echo "time: $(date --iso-8601=seconds)"
    echo
    complete=0
    failed=0
    for track in "${tracks[@]}"; do
        status_file="$STATUS_DIR/${track}.status"
        if [[ -f "$status_file" ]]; then
            line="$(cat "$status_file")"
            echo "$track: $line"
            complete=$((complete + 1))
            if [[ "$line" == failed* ]]; then failed=$((failed + 1)); fi
        else
            echo "$track: running"
        fi
    done
    if [[ $complete -eq ${#tracks[@]} && $sent_overall -eq 0 ]]; then
        overall="passed"
        if [[ $failed -ne 0 ]]; then overall="failed"; fi
        printf '%s failed=%s finished_at=%s out=%s\n' "$overall" "$failed" "$(date --iso-8601=seconds)" "$OUT" > "$STATUS_DIR/overall.status"
        notify "rom_fourway overall ${overall} failed=${failed} out=${OUT}"
        sent_overall=1
    fi
    echo
    echo "recent log tails:"
    for log in "$LOGS"/*.log; do
        [[ -f "$log" ]] || continue
        echo
        echo "== $(basename "$log") =="
        tail -n 12 "$log"
    done
    sleep 30
done
EOF

chmod +x "$OUT/scripts/"*.sh

tmux new-session -d -s "$SESSION" -n audit "bash '$OUT/scripts/audit.sh'"
tmux set-option -t "$SESSION" remain-on-exit on
tmux new-window -t "$SESSION" -n control "bash '$OUT/scripts/probe_task.sh' rom_control_probe '$ROOT/configs/hls4ml_runs/diagnostics/rom_control_probe_aclk100.yaml'"
tmux new-window -t "$SESSION" -n layer "bash '$OUT/scripts/probe_task.sh' rom_layer_probe '$ROOT/configs/hls4ml_runs/diagnostics/rom_layer_probe_aclk100.yaml'"
tmux new-window -t "$SESSION" -n coyote_existing "bash '$OUT/scripts/existing_coyote.sh'"
tmux new-window -t "$SESSION" -n status "bash '$OUT/scripts/status.sh'"
tmux select-window -t "$SESSION:status"

echo "session=$SESSION"
echo "out=$OUT"
echo "attach=tmux attach -t $SESSION"
