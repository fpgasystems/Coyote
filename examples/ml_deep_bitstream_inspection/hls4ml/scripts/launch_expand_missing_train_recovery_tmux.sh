#!/usr/bin/env bash
set -euo pipefail

ROOT="/pub/scratch/sdeheredia/Coyote/examples/ml_deep_bitstream_inspection/hls4ml"
SESSION="${1:-hls4ml_expand_missing_train_recovery}"
TOPIC="coyote-build-sdeheredia"
TS="$(date +%Y%m%d_%H%M%S)"
LOG_ROOT="$ROOT/logs/expand_missing_train_recovery/$TS"
PY="$ROOT/../.venv_hls4ml/bin/python"
CONFIG_ROOT="configs/hls4ml_expand_missing_train_recovery"
XILINX_VERSION="${XILINX_VERSION:-2024.2}"

if tmux has-session -t "$SESSION" 2>/dev/null; then
  echo "tmux session already exists: $SESSION" >&2
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
make_configs() {
  '$PY' - <<'PY'
import csv, shutil
from pathlib import Path

status_path = Path('results/expand_sweep/suite_status.csv')
out = Path('$CONFIG_ROOT')
out.mkdir(parents=True, exist_ok=True)
for old in out.glob('*.yaml'):
    old.unlink()

rows = list(csv.DictReader(status_path.open())) if status_path.exists() else []
active_or_done_train_hls = {
    row.get('experiment_name', '')
    for row in rows
    if row.get('requested_stages') == 'train,hls' and row.get('status') in {'running', 'success'}
}
selected = []
for row in rows:
    name = row.get('experiment_name', '')
    if row.get('status') != 'failed':
        continue
    if row.get('requested_stages') != 'hls':
        continue
    if name in active_or_done_train_hls:
        continue
    log = row.get('failure_reason', '').split('log=', 1)[-1]
    log_text = Path(log).read_text(errors='ignore') if log and Path(log).exists() else row.get('failure_reason', '')
    if 'Missing trained primary fold' not in log_text:
        continue
    config = Path(row.get('config_path', ''))
    if config.exists():
        selected.append(config)

for config in sorted(set(selected)):
    shutil.copy2(config, out / config.name)
print(f'[expand-missing-train] configs={len(list(out.glob(\"*.yaml\")))} dir={out}')
PY
}
trap 'status=\$?; notify \"expand missing-train recovery FAILED status=\$status session=$SESSION log=$LOG_ROOT/supervisor.log\"; exit \$status' ERR
exec > >(tee -a '$LOG_ROOT/supervisor.log') 2>&1
notify \"expand missing-train recovery launched: session=$SESSION logs=$LOG_ROOT\"
export TERM=\${TERM:-xterm}
set +u
source \"/tools/Xilinx/Vivado/$XILINX_VERSION/settings64.sh\"
source \"/tools/Xilinx/Vitis/$XILINX_VERSION/settings64.sh\"
source \"/tools/Xilinx/Vitis_HLS/$XILINX_VERSION/settings64.sh\"
set -u
export HLS4ML_RUN_TOOLCHAIN_ENABLED=1
which vitis_hls
which vivado
make_configs
count=\$(find '$CONFIG_ROOT' -maxdepth 1 -name '*.yaml' | wc -l)
echo \"[expand-missing-train] start configs=\$count log_dir=$LOG_ROOT/train_hls\"
if [ \"\$count\" -gt 0 ]; then
  mkdir -p '$LOG_ROOT/train_hls'
  notify \"expand missing-train train+hls started: configs=\$count session=$SESSION logs=$LOG_ROOT/train_hls\"
  '$PY' scripts/run_experiment_configs_parallel.py \
    --configs '$CONFIG_ROOT' \
    --phases 4,4.5 \
    --stages train,hls \
    --results-dir results/expand_sweep \
    --log-dir '$LOG_ROOT/train_hls' \
    --jobs 8 \
    --hls-timeout 10h \
    --force-fingerprint
fi
summary=\$(status_summary)
notify \"expand missing-train recovery complete: \$summary session=$SESSION logs=$LOG_ROOT\"
echo \"[expand-missing-train] complete \$summary logs=$LOG_ROOT\"
"

echo "session=$SESSION"
echo "attach=tmux attach -t $SESSION"
echo "log=$LOG_ROOT/supervisor.log"
