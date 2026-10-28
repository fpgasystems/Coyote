#!/usr/bin/env bash
# Build and install one Verilator release or commit from source, without root.
#
# Usage: sim/vl/install_verilator.sh <prefix>
#        sim/vl/install_verilator.sh <ref> <prefix> [src dir]
#   <prefix>   install folder, e.g. $HOME/opt/verilator/v5.052; put <prefix>/bin in PATH afterwards
#   <ref>      release tag, e.g. v5.052 (`git tag -l 'v5.*'` in the clone lists them), or a commit hash;
#              without it, VERILATOR_REF of sim/vl/verilator.env (the pin of this simulation)
#   [src dir]  the source clone (default: <prefix>/../src/verilator; reused when it exists)
#
# Does nothing when <prefix> already holds <ref>. The clone is blobless (git 2.27 or newer).
# Needs git, autoconf, flex, bison, help2man, g++, make, perl, python3. JOBS sets the compile jobs.
set -euo pipefail

. "$(dirname "$(realpath "$0")")/verilator.env"
case $# in
    1) REF=$VERILATOR_REF; PREFIX=$(realpath -m "$1"); SRC=$(dirname "$PREFIX")/src/verilator ;;
    2|3) REF=$1; PREFIX=$(realpath -m "$2"); SRC=${3:-$(dirname "$PREFIX")/src/verilator} ;;
    *) echo "usage: $0 <prefix>  |  $0 <ref> <prefix> [src dir]" >&2; exit 1 ;;
esac

# The rev is the tag, or <tag>-<n>-g<hash> for a commit (verilator.env); the first seven characters
# of <ref> match the hash, so a short and a full hash both count.
case "$(verilator_rev "$PREFIX/bin/verilator")" in
    "$REF"|*-g"${REF:0:7}"*)
        echo "$PREFIX already holds Verilator $REF"
        exit 0 ;;
esac

for t in git autoconf flex bison help2man g++ make perl python3; do
    command -v "$t" > /dev/null || { echo "missing tool: $t" >&2; exit 1; }
done

if [ ! -d "$SRC/.git" ]; then
    mkdir -p "$(dirname "$SRC")"
    git clone --filter=blob:none https://github.com/verilator/verilator.git "$SRC"
fi
cd "$SRC"
git rev-parse -q --verify "$REF^{commit}" > /dev/null || git fetch --tags origin
git checkout -q "$REF"
[ configure -nt configure.ac ] || autoconf
./configure --prefix="$PREFIX"
make -j "${JOBS:-$(nproc)}"
make install
"$PREFIX/bin/verilator" --version
