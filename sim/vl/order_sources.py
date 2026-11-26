# Print the source files read from stdin: the package files first, each after the packages it
# references (`name::`), then the other files in their order. Verilator needs a package before its users.
# Usage: ... | python3 sim/vl/order_sources.py   (sim/vl/configure.sh writes files.f with it)
import re
import sys
from graphlib import TopologicalSorter

files = [l.strip() for l in sys.stdin if l.strip()]
text = {f: open(f).read() for f in files}
pkgs = {m: f for f in files for m in re.findall(r'^\s*package\s+(\w+)', text[f], re.M)}
deps = {n: {d for d in re.findall(r'\b(\w+)::', text[f]) if d in pkgs and d != n} for n, f in pkgs.items()}
order = list(dict.fromkeys(pkgs[n] for n in TopologicalSorter(deps).static_order()))
print('\n'.join(order + [f for f in files if f not in order]))
