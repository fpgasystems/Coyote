#!/usr/bin/env python3
"""Mechanical hygiene checks on a PR worktree: layers touched, whitespace-only
changes, artefacts, unmaintained paths, submodule bumps, licence headers.
Usage: hygiene.py <head-worktree> <merge-base-sha>"""
import re
import subprocess
import sys

tree, base = sys.argv[1], sys.argv[2]


def git(*args):
    return subprocess.run(["git", "-C", tree, *args], capture_output=True, text=True).stdout


LAYERS = [
    ("hw-static", r"^hw/(hdl/static|templates/[^/]+/static_top|bd/[^/]+/cr_pci|checkpoints)"),
    ("hw-mmu", r"^hw/hdl/mmu/"),
    ("hw-memory", r"^hw/(hdl/(stripe|cdma)|bd/[^/]+/cr_(hbm|ddr))|^hw/hdl/shell/hbm_wide"),
    ("hw-network", r"^hw/(hdl/network|services/network)"),
    ("hw-shell", r"^hw/(hdl/shell|templates/common/(shell|dynamic|cyt|lynx|user_clk)|templates/[^/]+/(dynamic_xbar|shell_clk)|bd/[^/]+/cr_ctrl)"),
    ("hw-user", r"^hw/(hdl/user|templates/common/user_(wrapper|logic))|^hw/hdl/pkg/"),
    ("hw-common", r"^hw/hdl/common/"),
    ("hw-constraints", r"^hw/constraints/"),
    ("hw-other", r"^hw/"),
    ("driver", r"^driver/"),
    ("sw", r"^sw/"),
    ("sim", r"^sim/"),
    ("examples", r"^examples/"),
    ("build", r"^(cmake|scripts)/|CMakeLists\.txt$"),
    ("ci", r"^\.github/"),
    ("docs", r"^docs/|\.(md|rst)$"),
]
ARTEFACT = re.compile(r"(^|/)(build[^/]*|\.Xil|\.vscode|\.idea|__pycache__)/|\.(bit|pdi|dcp|ltx|log|jou|o|ko|so|a|pyc|wdb|vcd)$")
UNMAINTAINED = re.compile(r"(^|/)LEGACY/|^hw/constraints/(u200|u50|vcu118|enzian)/")
LICENSE_EXT = (".sv", ".v", ".svh", ".c", ".h", ".cpp", ".hpp", ".tcl", ".py", ".cmake", ".txt")

status = [l.split("\t") for l in git("diff", "--name-status", base, "HEAD").splitlines() if l]
paths = [s[-1] for s in status]

print("## Layers touched")
layers = {}
for p in paths:
    for name, rx in LAYERS:
        if re.search(rx, p):
            layers.setdefault(name, []).append(p)
            break
    else:
        layers.setdefault("other", []).append(p)
for name, ps in layers.items():
    print(f"- {name}: {len(ps)} file(s)")

print("\n## Whitespace-only changes (lines changed that vanish under -w)")
full = {l.split("\t")[2]: l.split("\t")[:2] for l in git("diff", "--numstat", base, "HEAD").splitlines()}
ws = {l.split("\t")[2]: l.split("\t")[:2] for l in git("diff", "--numstat", "-w", "--ignore-blank-lines", base, "HEAD").splitlines()}
found = False
for p, (a, d) in full.items():
    if a == "-":
        continue
    a2, d2 = ws.get(p, ("0", "0"))
    extra = (int(a) + int(d)) - (int(a2) + int(d2))
    if extra > 0:
        found = True
        tag = "WHITESPACE-ONLY FILE" if a2 == d2 == "0" else f"{extra} whitespace-only line(s)"
        print(f"- {p}: {tag}")
if not found:
    print("- none")
crlf = [p for p in paths if p in full and "\r" in git("diff", base, "HEAD", "--", p)]
if crlf:
    print("- CRLF line endings introduced in: " + ", ".join(crlf))
no_eol = []
for p in paths:
    if p not in full or full[p][0] == "-":
        continue
    lines = git("diff", base, "HEAD", "--", p).splitlines()
    for i, l in enumerate(lines):
        if l.startswith("\\ No newline at end of file") and i > 0 and lines[i - 1].startswith("+"):
            no_eol.append(p)
            break
if no_eol:
    print("- Missing final newline in: " + ", ".join(no_eol))

print("\n## Flags")
flags = []
for s in status:
    code, p = s[0], s[-1]
    if ARTEFACT.search(p):
        flags.append(f"ARTEFACT? {p}")
    if UNMAINTAINED.search(p):
        flags.append(f"UNMAINTAINED path touched: {p}")
    if code.startswith("A") and p.endswith(LICENSE_EXT):
        head = git("show", f"HEAD:{p}")[:2000]
        if not re.search(r"MIT|GNU General Public License|Licen[cs]e", head):
            flags.append(f"NO LICENCE HEADER in new file: {p}")
        elif p.startswith("driver/") and "GNU General Public" not in head:
            flags.append(f"Driver file without GPL header: {p}")
sub = [l for l in git("diff", "--raw", base, "HEAD").splitlines() if " 160000 " in l or l.startswith(":160000")]
for l in sub:
    flags.append(f"SUBMODULE pointer changed: {l.split()[-1]}")
binaries = [l.split("\t")[2] for l in git("diff", "--numstat", base, "HEAD").splitlines() if l.startswith("-\t-\t")]
for b in binaries:
    flags.append(f"BINARY file: {b}")
regs = [p for p in paths if re.search(r"cnfg_slave(_avx)?\.sv$|shell_slave\.sv$|coyote_defs\.h$|cDefs\.hpp$", p)]
if regs:
    flags.append("REGISTER-SYNC files touched (check B5): " + ", ".join(regs))
api = [p for p in paths if re.search(r"^sw/include/coyote/|^hw/hdl/pkg/lynx_intf\.sv$|user_(logic|wrapper)_tmplt|lynx_pkg_tmplt", p)]
if api:
    flags.append("USER-FACING API files touched (check B1/B2/B3): " + ", ".join(api))
if any(p.startswith("sw/src/cThread") or p.startswith("sw/include/coyote/cThread") for p in paths) and not any(p.startswith("sim/sw") for p in paths):
    flags.append("cThread changed but sim/sw not touched (check B7)")
if any(p.startswith(("driver/", "hw/", "sw/include")) for p in paths) and not any(p.startswith("docs/") for p in paths):
    flags.append("Code changed but no docs/ change (check E6)")
print("\n".join(f"- {f}" for f in flags) if flags else "- none")
