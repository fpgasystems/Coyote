#!/usr/bin/env bash
# Build the merge base and the PR head the same way and report NEW warnings/errors.
# Usage: build_checks.sh <review-dir>       (the directory printed by prepare.sh)
# Runs only the builds relevant to the touched paths. Never runs Vivado.
set -uo pipefail

DIR="${1:?usage: build_checks.sh <review-dir>}"
FILES="$DIR/files.txt"
LOG="$DIR/build"
mkdir -p "$LOG"
REPORT="$DIR/build_report.md"
: > "$REPORT"

touched() { cut -f2- "$FILES" | tr '\t' '\n' | grep -qE "$1"; }

# Strip tree paths and line/column numbers so identical warnings compare equal across trees.
normalise() {
    sed -E -e "s#$DIR/(head|base)/##g" -e 's#:[0-9]+:[0-9]+:#:#g' -e 's#:[0-9]+:#:#g' -e 's#%Warning-([A-Z0-9_]+): [^:]+:[0-9]+:[0-9]+:#%Warning-\1: #' \
        | grep -E "warning|error|Error|%Warning|%Error" | sort -u
}

# run <name> <command with @TREE@ placeholder>
run() {
    local name="$1" cmd="$2" rc_h rc_b
    for t in base head; do
        ( eval "${cmd//@TREE@/$DIR/$t}" ) > "$LOG/$name.$t.log" 2>&1
        echo $? > "$LOG/$name.$t.rc"
    done
    rc_b=$(cat "$LOG/$name.base.rc"); rc_h=$(cat "$LOG/$name.head.rc")
    normalise < "$LOG/$name.base.log" > "$LOG/$name.base.w"
    normalise < "$LOG/$name.head.log" > "$LOG/$name.head.w"
    local new; new=$(comm -13 "$LOG/$name.base.w" "$LOG/$name.head.w")
    local fixed; fixed=$(comm -23 "$LOG/$name.base.w" "$LOG/$name.head.w" | wc -l)
    {
        echo "### $name"
        echo "- exit code: base=$rc_b head=$rc_h $( [ "$rc_h" != 0 ] && [ "$rc_b" = 0 ] && echo '**HEAD FAILS, BASE BUILDS**')"
        echo "- new warnings/errors: $(printf '%s' "$new" | grep -c . )   (removed: $fixed)"
        [ -n "$new" ] && printf '%s\n' "$new" | head -40 | sed 's/^/    /'
        echo "- logs: $LOG/$name.{base,head}.log"
        echo
    } >> "$REPORT"
}

if touched '^driver/'; then
    for p in ultrascale_plus versal; do
        run "driver-$p" "make -C @TREE@/driver TARGET_PLATFORM=$p W=1 -j8 && make -C @TREE@/driver TARGET_PLATFORM=$p clean >/dev/null"
    done
fi

if touched '^(sw|sim/sw|cmake)/|^examples/[^/]+/sw/'; then
    EX=examples/01_hello_world/sw
    for cfg in "avx1:-DEN_AVX=1" "avx0:-DEN_AVX=0" "sim:-DEN_SIM=ON"; do
        n=${cfg%%:*}; flags=${cfg#*:}
        run "sw-$n" "cmake -S @TREE@/$EX -B @TREE@/_rb/sw-$n $flags -DCMAKE_CXX_FLAGS='-Wall -Wextra' >/dev/null && cmake --build @TREE@/_rb/sw-$n -j8"
    done
    for ex in $(cut -f2- "$FILES" | tr '\t' '\n' | grep -oE '^examples/[^/]+/sw' | sort -u); do
        [ "$ex" = "$EX" ] && continue
        n=$(basename "$(dirname "$ex")")
        run "sw-$n" "cmake -S @TREE@/$ex -B @TREE@/_rb/$n -DCMAKE_CXX_FLAGS='-Wall -Wextra' >/dev/null && cmake --build @TREE@/_rb/$n -j8"
    done
fi

# RTL: best-effort Verilator lint of touched non-template sources. Rendered packages and
# Vivado IP are unavailable, so missing-module/package errors appear on both sides and cancel.
RTL=$(cut -f2- "$FILES" | tr '\t' '\n' | grep -E '^hw/hdl/.*\.(sv|v)$' | grep -v LEGACY | sort -u)
if [ -n "$RTL" ] && command -v verilator >/dev/null; then
    for f in $RTL; do
        n="lint-$(basename "$f" | tr '.' '_')"
        run "$n" "[ -f @TREE@/$f ] && verilator --lint-only -Wall -Wno-fatal -Wno-DECLFILENAME -Wno-UNUSEDSIGNAL -I@TREE@/hw/hdl/pkg @TREE@/hw/hdl/pkg/axi_macros.svh @TREE@/hw/hdl/pkg/lynx_macros.svh @TREE@/$f"
    done
fi

if touched '^hw/(templates|bd|constraints)/|^scripts/' ; then
    echo "### HW project / synthesis" >> "$REPORT"
    echo "- NOT RUN: templates, BDs, constraints or scripts changed. Needs Vivado (\`cmake ../hw -DFDEV_NAME=<board> && make project\`, then synth). Ask the maintainer before running; it takes hours." >> "$REPORT"
fi

[ -s "$REPORT" ] || echo "No buildable paths touched (docs/CI only)." > "$REPORT"
cat "$REPORT"
