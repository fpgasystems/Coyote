/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:

 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.

 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

package sim_pkg;
    typedef logic[lynxTypes::VADDR_BITS - 1:0] vaddr_t;

    class mem_seg_t;
        vaddr_t vaddr;
        vaddr_t size;
        byte    data[];
        bit     marker;

        function new(vaddr_t vaddr, vaddr_t size, byte data[]);
            this.vaddr  = vaddr;
            this.size   = size;
            this.data   = data;
            this.marker = 0;
        endfunction
    endclass;

    class mem_t; // We need this as a wrapper because you cannot pass queues [$] by reference
        mem_seg_t segs[$];

        // Returns the segment that contains vaddr or null if there is none
        function mem_seg_t find_seg(vaddr_t vaddr);
            foreach (segs[i]) begin
                if (segs[i].vaddr <= vaddr && vaddr < segs[i].vaddr + segs[i].size) return segs[i];
            end
            return null;
        endfunction

        // Collects all segments that cover [vaddr, vaddr + len) in ascending order. Returns 0 if any
        // byte in the range is not covered. A range may span multiple adjacent segments, e.g., when
        // the pages of a buffer were mapped on separate page faults.
        function bit get_segs(vaddr_t vaddr, vaddr_t len, ref mem_seg_t result[$]);
            vaddr_t curr = vaddr;
            result.delete();
            while (curr < vaddr + len) begin
                mem_seg_t seg = find_seg(curr);
                if (seg == null) return 0;
                result.push_back(seg);
                curr = seg.vaddr + seg.size;
            end
            return 1;
        endfunction

        function bit is_mapped(vaddr_t vaddr, vaddr_t len);
            mem_seg_t segs_in_range[$];
            return get_segs(vaddr, len, segs_in_range);
        endfunction

        // Reads [vaddr, vaddr + len) into data. Returns 0 if the range is not fully mapped.
        function bit read(vaddr_t vaddr, vaddr_t len, ref byte data[]);
            mem_seg_t segs_in_range[$];
            if (!get_segs(vaddr, len, segs_in_range)) return 0;
            data = new[len];
            foreach (segs_in_range[i]) begin
                vaddr_t start = segs_in_range[i].vaddr > vaddr ? segs_in_range[i].vaddr : vaddr;
                vaddr_t stop  = segs_in_range[i].vaddr + segs_in_range[i].size < vaddr + len ? segs_in_range[i].vaddr + segs_in_range[i].size : vaddr + len;
                for (vaddr_t addr = start; addr < stop; addr++) begin
                    data[addr - vaddr] = segs_in_range[i].data[addr - segs_in_range[i].vaddr];
                end
            end
            return 1;
        endfunction

        // Writes data to [vaddr, vaddr + $size(data)). Returns 0 if the range is not fully mapped.
        function bit write(vaddr_t vaddr, ref byte data[]);
            mem_seg_t segs_in_range[$];
            if (!get_segs(vaddr, $size(data), segs_in_range)) return 0;
            foreach (segs_in_range[i]) begin
                vaddr_t start = segs_in_range[i].vaddr > vaddr ? segs_in_range[i].vaddr : vaddr;
                vaddr_t stop  = segs_in_range[i].vaddr + segs_in_range[i].size < vaddr + $size(data) ? segs_in_range[i].vaddr + segs_in_range[i].size : vaddr + $size(data);
                for (vaddr_t addr = start; addr < stop; addr++) begin
                    segs_in_range[i].data[addr - segs_in_range[i].vaddr] = data[addr - vaddr];
                end
            end
            return 1;
        endfunction
    endclass
endpackage
