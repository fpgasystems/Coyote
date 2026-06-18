#!/bin/bash
# Monitor active training runs and send progress via ntfy
TOPIC="coyote-build-sdeheredia"
NOW=$(date +%s)

msg=""
all_done=true

for session in train_aug train_noaug train_lr5 train_cnn_a train_cnn_b; do
    # Check if session exists
    if ! tmux has-session -t "$session" 2>/dev/null; then
        msg+="$session: FINISHED\n"
        continue
    fi
    all_done=false

    # Get last epoch line from pane (-J joins wrapped lines)
    last_line=$(tmux capture-pane -t "$session" -p -J -S -100 | grep -E '^\s*[0-9]+\s' | tail -1)
    if [ -z "$last_line" ]; then
        msg+="$session: starting up...\n"
        continue
    fi

    epoch=$(echo "$last_line" | awk '{print $1}')
    sec=$(echo "$last_line" | awk '{print $NF}' | sed 's/s//')

    case "$session" in
        train_aug)   total=2000; label="aug lr1e-4" ;;
        train_noaug) total=2000; label="noaug lr1e-4" ;;
        train_lr5)   total=2000; label="aug lr1e-5" ;;
        train_cnn_a) total=500;  label="cnn_a ro8k" ;;
        train_cnn_b) total=500;  label="cnn_b ro8k" ;;
    esac

    remaining=$(python3 -c "
r = ($total - $epoch) * $sec / 3600
h = int(r)
m = int((r - h) * 60)
print(f'{h}h{m:02d}m')
")
    pct=$((epoch * 100 / total))

    # Extract summary stats from last epoch line
    # Columns: Ep TrLoss VaBCE AugBCE Acc AugAcc AUC AugAUC Time
    stats=$(echo "$last_line" | awk '{printf "Acc=%s AugAcc=%s AUC=%s AugAUC=%s", $5, $6, $7, $8}')

    msg+="$session ($label): ${epoch}/${total} (${pct}%) ETA ${remaining}\n  ${stats}\n"
done

# Send notification
curl -s -d "$(echo -e "ML Training Status $(date '+%H:%M')\n${msg}")" ntfy.sh/$TOPIC > /dev/null

# If all done, remove the cron job
if $all_done; then
    crontab -l 2>/dev/null | grep -v "monitor_runs.sh" | crontab -
    curl -s -d "All ML training runs complete!" ntfy.sh/$TOPIC > /dev/null
fi
