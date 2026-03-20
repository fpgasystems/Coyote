#!/usr/bin/env python3
"""Generate nodbg (no-debug/ILA) variants of benign apps.

For each base app, copies the entire directory and then:
  1. Removes ILA instantiation block from vfpga_top.svh
  2. Strips ILA IP creation from init_ip.tcl (keeps non-ILA IPs)

Usage:
    python3 gen_nodbg_variants.py
"""

import os
import re
import shutil

BASE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
BENIGN_DIR = os.path.join(BASE, "hw", "apps", "benign")
VARIANT_DIR = os.path.join(BASE, "hw", "apps", "benign_variants")

# Map: variant_id -> (base_app_id, ila_module_name)
VARIANTS = {
    "V01_hello_world_nodbg":        ("A01_hello_world",        "ila_perf_host"),
    "V02_hls_vadd_nodbg":           ("A02_hls_vadd",           "ila_vadd"),
    "V03_multitenancy_aes_nodbg":   ("A03_multitenancy_aes",   "ila_aes"),
    "V04_user_interrupts_nodbg":    ("A04_user_interrupts",    "ila_vfpga_interrupt"),
    "V05_perf_fpga_nodbg":          ("A05_perf_fpga",          "ila_perf_fpga"),
    "V06_multithreading_aes_nodbg": ("A06_multithreading_aes", "ila_aes_mt"),
    "V07_euclidean_nodbg":          ("A07_euclidean",          "ila_distance"),
}


def strip_ila_from_vfpga(content, ila_name):
    """Remove ILA instantiation block from vfpga_top.svh."""
    if ila_name is None:
        return content

    # Pattern: optional comment lines before ILA, then ila_name <inst> ( ... );
    pattern = (
        r'(?:(?://[^\n]*(?:ILA|ila|debug|Debug)[^\n]*\n)*)'  # optional comment lines
        r'\s*' + re.escape(ila_name) + r'\s+\w+\s*\('        # ila_name inst_name (
        r'[^;]*\);'                                           # everything up to );
    )
    result = re.sub(pattern, '', content, flags=re.DOTALL)

    # Clean up multiple blank lines
    result = re.sub(r'\n{3,}', '\n\n', result)
    return result


def strip_ila_from_init_ip(content, ila_name):
    """Remove ILA IP creation from init_ip.tcl, keep other IPs.

    Handles the common pattern:
        # comment
        if {$cfg(fpga_arch) eq "ultrascale_plus"} {
            create_ip ... -module_name ila_XXX
        } elseif ...
        }
        set_property ... [get_ips ila_XXX]
    """
    if ila_name is None:
        return content

    # Strategy: find all blocks that reference the ILA name and remove them.
    # A "block" is either:
    #   1. An if/elseif/else block containing the ILA name
    #   2. A set_property line referencing the ILA name
    #   3. A comment line immediately before such a block

    lines = content.split('\n')
    # First pass: mark lines that are part of ILA-related blocks
    remove = [False] * len(lines)

    i = 0
    while i < len(lines):
        line = lines[i]

        # Check if this line or the next few lines reference the ILA
        if ila_name in line:
            # If it's inside an if block, find the full if/elseif/else/end block
            # Look backwards for the start of the if block
            start = i
            while start > 0 and lines[start].strip() not in ('', ) and not lines[start].strip().startswith('if '):
                # Check if previous line is a comment or part of the block
                prev = lines[start - 1].strip()
                if prev.startswith('#') or prev.startswith('} elseif') or prev.startswith('} else'):
                    start -= 1
                else:
                    break

            # If we're at an 'if' line or went back to one
            if any('if {' in lines[j] or 'if{' in lines[j] for j in range(max(0, start - 1), min(len(lines), i + 1))):
                # Find the start of the if block
                block_start = start
                for j in range(start, -1, -1):
                    if lines[j].strip().startswith('if ') or lines[j].strip().startswith('if{'):
                        block_start = j
                        break
                    elif lines[j].strip().startswith('#'):
                        block_start = j
                    elif lines[j].strip() == '':
                        break
                    else:
                        break

                # Find the end of the if block (matching closing brace)
                block_end = i
                brace_depth = 0
                for j in range(block_start, len(lines)):
                    brace_depth += lines[j].count('{') - lines[j].count('}')
                    if brace_depth <= 0 and j >= i:
                        block_end = j
                        break

                # Mark the entire block for removal
                for j in range(block_start, block_end + 1):
                    remove[j] = True

                i = block_end + 1
                continue

            # Otherwise just mark this line
            remove[i] = True
            i += 1
            continue

        i += 1

    # Also mark set_property lines that reference the ILA
    for i, line in enumerate(lines):
        if ila_name in line and 'set_property' in line:
            remove[i] = True

    # Build result, keeping non-removed lines
    result_lines = [line for line, rm in zip(lines, remove) if not rm]
    result = '\n'.join(result_lines)

    # Clean up
    result = re.sub(r'\n{3,}', '\n\n', result)

    # If file is now effectively empty, add placeholder
    if not any(l.strip() for l in result.split('\n') if not l.strip().startswith('#') and l.strip()):
        result = "# No IPs required (ILA removed for nodbg variant).\n"

    return result


def main():
    os.makedirs(VARIANT_DIR, exist_ok=True)

    for variant_id, (base_id, ila_name) in VARIANTS.items():
        src_dir = os.path.join(BENIGN_DIR, base_id)
        dst_dir = os.path.join(VARIANT_DIR, variant_id)

        if not os.path.exists(src_dir):
            print(f"  SKIP {variant_id}: base {base_id} not found at {src_dir}")
            continue

        # Copy entire directory
        if os.path.exists(dst_dir):
            shutil.rmtree(dst_dir)
        shutil.copytree(src_dir, dst_dir)

        # Strip ILA from vfpga_top.svh
        vfpga_path = os.path.join(dst_dir, "vfpga_top.svh")
        if os.path.exists(vfpga_path):
            with open(vfpga_path, 'r') as f:
                content = f.read()
            content = strip_ila_from_vfpga(content, ila_name)
            # Add nodbg header comment
            header = f"// nodbg variant of {base_id} — ILA ({ila_name}) removed\n"
            if content.startswith('//'):
                content = header + content[content.index('\n') + 1:]
            else:
                content = header + content
            with open(vfpga_path, 'w') as f:
                f.write(content)

        # Strip ILA from init_ip.tcl
        init_ip_path = os.path.join(dst_dir, "init_ip.tcl")
        if os.path.exists(init_ip_path):
            with open(init_ip_path, 'r') as f:
                content = f.read()
            content = strip_ila_from_init_ip(content, ila_name)
            with open(init_ip_path, 'w') as f:
                f.write(content)

        print(f"  Created {variant_id} (from {base_id}, stripped {ila_name})")

    print(f"\nGenerated {len(VARIANTS)} nodbg variant directories in {VARIANT_DIR}")


if __name__ == "__main__":
    main()
