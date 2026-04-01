#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="$SCRIPT_DIR/.venv"
PYTHON_BIN="$VENV_DIR/bin/python"
PORT="${1:-8888}"
HOSTNAME_FQDN="$(hostname -f)"
KERNEL_NAME="ml-baseline-venv"
KERNEL_DISPLAY_NAME="ml_baseline .venv"

if [ ! -x "$PYTHON_BIN" ]; then
    echo "Missing virtual environment at $VENV_DIR"
    echo "Run: $SCRIPT_DIR/setup_env.sh"
    exit 1
fi

source "$VENV_DIR/bin/activate"
cd "$SCRIPT_DIR"

if ! python -c "import jupyterlab" >/dev/null 2>&1; then
    echo "Installing JupyterLab into $VENV_DIR ..."
    python -m pip install jupyterlab
fi

if ! python -c "import ipykernel" >/dev/null 2>&1; then
    echo "Installing ipykernel into $VENV_DIR ..."
    python -m pip install ipykernel
fi

python -m ipykernel install --user --name "$KERNEL_NAME" --display-name "$KERNEL_DISPLAY_NAME" >/dev/null

echo "Jupyter directory: $SCRIPT_DIR"
echo "Notebook: $SCRIPT_DIR/resnet18_baseline.ipynb"
echo "Kernel: $KERNEL_DISPLAY_NAME"
echo "Cluster host: $HOSTNAME_FQDN"
echo "Port: $PORT"
echo ""
echo "If you are not already in tmux:"
echo "  tmux new -s jupyter"
echo ""
echo "From your laptop, forward the port with:"
echo "  ssh -L ${PORT}:localhost:${PORT} <your_user>@${HOSTNAME_FQDN}"
echo ""
echo "Starting JupyterLab ..."

exec python -m jupyter lab \
    --no-browser \
    --ip=127.0.0.1 \
    --port="$PORT" \
    --notebook-dir="$SCRIPT_DIR"
