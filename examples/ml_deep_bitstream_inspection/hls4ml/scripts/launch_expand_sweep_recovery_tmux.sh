#!/usr/bin/env bash
set -euo pipefail

ROOT="/pub/scratch/sdeheredia/Coyote/examples/ml_deep_bitstream_inspection/hls4ml"
SESSION="${1:-hls4ml_expand_sweep_recovery}"
TOPIC="coyote-build-sdeheredia"
TS="$(date +%Y%m%d_%H%M%S)"
LOG_ROOT="$ROOT/logs/expand_sweep_recovery/$TS"
PY="$ROOT/../.venv_hls4ml/bin/python"
RECOVERY_ROOT="configs/hls4ml_expand_sweep_recovery"
XILINX_VERSION="${XILINX_VERSION:-2024.2}"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "tmux session already exists: $SESSION" >&2
  exit 1
fi

if tmux has-session -t hls4ml_expand_sweep 2>/dev/null; then
  echo "broken hls4ml_expand_sweep session is still running; stop it before recovery" >&2
  echo "run: tmux kill-session -t hls4ml_expand_sweep" >&2
  exit 1
fi

mkdir -p "$LOG_ROOT"

tmux new-session -d -s "$SESSION" bash -lc "
set -euo pipefail
cd '$ROOT'
mkdir -p '$LOG_ROOT'
notify() { curl -s -d \"\$*\" ntfy.sh/$TOPIC >/dev/null || true; }
status_summary() {
  '$PY' - <<'PY'
import csv, collections
from pathlib import Path
p = Path('results/expand_sweep/suite_status.csv')
rows = list(csv.DictReader(p.open())) if p.exists() else []
print('rows=' + str(len(rows)) + ' ' + ' '.join(f'{k}={v}' for k,v in sorted(collections.Counter(r.get('status','') for r in rows).items())))
PY
}
make_recovery_dirs() {
  '$PY' - <<'PY'
import csv, shutil
from pathlib import Path

status_path = Path('results/expand_sweep/suite_status.csv')
root = Path('$RECOVERY_ROOT')
groups = {
    'phase4_hls': [],
    'phase45_hls': [],
    'phase45_train_hls': [],
}
if status_path.exists():
    for row in csv.DictReader(status_path.open()):
        phase = str(row.get('phase', ''))
        status = row.get('status', '')
        config = row.get('config_path', '')
        if not config:
            continue
        if status == 'failed' and phase == '4':
            groups['phase4_hls'].append(config)
        elif status == 'failed' and phase == '4.5':
            groups['phase45_hls'].append(config)
        elif status == 'running' and phase == '4.5':
            groups['phase45_train_hls'].append(config)

for name, configs in groups.items():
    out = root / name
    out.mkdir(parents=True, exist_ok=True)
    for old in out.glob('*.yaml'):
        old.unlink()
    for config in sorted(set(configs)):
        src = Path(config)
        if src.exists():
            shutil.copy2(src, out / src.name)
    print(f'[expand-recovery] {name} configs={len(list(out.glob(\"*.yaml\")))}')
PY
}
run_group() {
  local label=\"\$1\"
  local phases=\"\$2\"
  local stages=\"\$3\"
  local config_dir=\"$RECOVERY_ROOT/\$label\"
  run_config_dir \"\$label\" \"\$config_dir\" \"\$phases\" \"\$stages\"
}
run_config_dir() {
  local label=\"\$1\"
  local config_dir=\"\$2\"
  local phases=\"\$3\"
  local stages=\"\$4\"
  local log_dir=\"$LOG_ROOT/\$label\"
  mkdir -p \"\$log_dir\"
  local count
  count=\$(find \"\$config_dir\" -maxdepth 1 -name '*.yaml' 2>/dev/null | wc -l)
  echo \"[expand-recovery] start \$label pending=\$count stages=\$stages\"
  if [ \"\$count\" -eq 0 ]; then
    return 0
  fi
  notify \"expand recovery \$label started: pending=\$count session=$SESSION logs=\$log_dir\"
  '$PY' scripts/run_experiment_configs_parallel.py \
    --configs \"\$config_dir\" \
    --phases \"\$phases\" \
    --stages \"\$stages\" \
    --results-dir results/expand_sweep \
    --log-dir \"\$log_dir\" \
    --jobs 8 \
    --hls-timeout 10h \
    --force-fingerprint
  echo \"[expand-recovery] finished \$label \$(status_summary)\"
  notify \"expand recovery \$label finished: \$(status_summary) session=$SESSION logs=\$log_dir\"
}
collect_expand() {
  '$PY' scripts/collect_experiment_results.py \
    --configs configs/hls4ml_expand_sweep \
    --artifacts artifacts_expand_sweep \
    --results-dir results/expand_sweep
}
aggregate_global() {
  '$PY' scripts/stable_collect_global.py \
    --base-configs configs/hls4ml_experiment \
    --base-results results \
    --global-configs configs/hls4ml_experiment_global \
    --global-results results \
    --artifacts artifacts \
    --extra configs/hls4ml_experiment_layer6_ext results_layer6_ext \
    --extra configs/hls4ml_experiment_layer7_ext results_layer7_ext \
    --extra configs/hls4ml_experiment_2048x6 results_2048x6 \
    --extra configs/hls4ml_selected_feasible_candidates results/selected_feasible_candidates \
    --extra configs/hls4ml_expand_sweep results/expand_sweep \
    --snapshot
}
trap 'status=\$?; notify \"expand recovery FAILED status=\$status session=$SESSION log=$LOG_ROOT/supervisor.log\"; exit \$status' ERR
exec > >(tee -a '$LOG_ROOT/supervisor.log') 2>&1
notify \"expand recovery launched: session=$SESSION logs=$LOG_ROOT\"
export CLI_PATH=/opt/hdev/cli
export TERM=\${TERM:-xterm}
set +u
source \"/tools/Xilinx/Vivado/$XILINX_VERSION/settings64.sh\"
source \"/tools/Xilinx/Vitis/$XILINX_VERSION/settings64.sh\"
source \"/tools/Xilinx/Vitis_HLS/$XILINX_VERSION/settings64.sh\"
set -u
export HLS4ML_RUN_TOOLCHAIN_ENABLED=1
which vitis_hls
which vivado
make_recovery_dirs
run_group phase4_hls 4 hls
run_group phase45_hls 4.5 hls
run_group phase45_train_hls 4.5 train,hls
collect_expand
'$PY' scripts/prepare_expand_sweep.py phase5
run_config_dir phase5 configs/hls4ml_expand_sweep_pending/phase5 5 hls
collect_expand
aggregate_global
'$PY' scripts/prepare_expand_sweep.py update-doc
summary=\$(status_summary)
notify \"expand recovery complete: \$summary session=$SESSION results=$ROOT/results/expand_sweep\"
echo \"[expand-recovery] complete \$summary logs=$LOG_ROOT\"
"

echo "session=$SESSION"
echo "attach=tmux attach -t $SESSION"
echo "log=$LOG_ROOT/supervisor.log"
