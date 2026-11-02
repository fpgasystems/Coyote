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

`ifndef SIM_PARAMS_SVH
`define SIM_PARAMS_SVH

`include "log.svh"

// dpi/file_io.c
import "DPI-C" function real coyote_sim_env_real(input string name, input real dflt);

/**
 * Rate limit of one direction of a mock: a token bucket in bytes that gains
 * bytes_per_cycle every clock and holds at most two beats.
 */
class token_bucket;
    localparam int BEAT_BYTES = AXI_DATA_BITS / 8;
    localparam real BUCKET_BYTES = 2.0 * BEAT_BYTES;

    real     bytes_per_cycle; // 0 is no limit
    real     tokens = BUCKET_BYTES;
    realtime filled_at = 0;

    function new(input real bytes_per_cycle);
        this.bytes_per_cycle = bytes_per_cycle;
    endfunction

    // One beat from the bucket; 0 when the bucket is short.
    // Refills from the time since the last call, so one bucket serves all streams of the mock.
    function bit take();
        if (bytes_per_cycle == 0) return 1;

        tokens += ($realtime - filled_at) / CLK_PERIOD * bytes_per_cycle;
        filled_at = $realtime;
        if (tokens > BUCKET_BYTES) tokens = BUCKET_BYTES;

        if (tokens < BEAT_BYTES) return 0;
        tokens -= BEAT_BYTES;
        return 1;
    endfunction
endclass

/**
 * xorshift32 random numbers for jitter and drops.
 * One instance per stream and direction.
 * Independent of EN_RANDOMIZATION (driver delays).
 * Is reproducible across xsim and verilator.
 */
class sim_rng;
    bit[31:0] state;

    function new(input int seed, input string name, input int dest, input bit wr);
        // FNV-1a over the seed, the mock name, the stream index and the direction
        bit[31:0] h = 32'h811c9dc5;
        h = (h ^ seed) * 32'h01000193;
        for (int i = 0; i < name.len(); i++) h = (h ^ name[i]) * 32'h01000193;
        h = (h ^ dest) * 32'h01000193;
        h = (h ^ wr) * 32'h01000193;
        // Finalizer of MurmurHash3
        h = (h ^ (h >> 16)) * 32'h85ebca6b;
        h = (h ^ (h >> 13)) * 32'hc2b2ae35;
        h = h ^ (h >> 16);
        state = (h == 0) ? 32'h1 : h;
    endfunction

    // Uniform in [0, 1)
    function real uniform();
        longint unsigned v;
        state = state ^ (state << 13);
        state = state ^ (state >> 17);
        state = state ^ (state << 5);
        v = state;
        return v / 4294967296.0;
    endfunction
endclass

/**
 * Timing parameters of one memory mock, read once from the environment:
 * COYOTE_SIM_<KEY>_LATENCY_NS, _GBPS, _MTU, _JITTER_NS, _DROP and _RETRANSMIT_NS, KEY = HOST, CARD or RDMA,
 * and COYOTE_SIM_SEED for all mocks.
 * Variables, defaults, the token bucket and the loss model: sim/README.md, "Timing parameters".
 * Mocks that share a port (the two RDMA mocks) share one object, so they share the buckets.
 */
class mock_params;
    realtime     latency;
    int          mtu;        // bytes between two tlast on data out of the mock; 0 is one tlast per request
    token_bucket rd;         // data out of the mock (read responses)
    token_bucket wr;         // data into the mock (writes)
    realtime     jitter;     // extra wait of a request, uniform in [0, jitter]
    real         drop;       // chance that one MTU (with mtu 0 the whole transfer) is lost and resent
    realtime     retransmit; // stall of the stream after a loss
    int          seed;       // seed of the sim_rng of every stream

    function new(input string key);
        real gbps = coyote_sim_env_real({"COYOTE_SIM_", key, "_GBPS"}, 0.0);
        real mtu_env = coyote_sim_env_real({"COYOTE_SIM_", key, "_MTU"}, 0.0);
        real bytes_per_cycle;

        latency = coyote_sim_env_real({"COYOTE_SIM_", key, "_LATENCY_NS"}, 50.0) * 1ns;
        jitter = coyote_sim_env_real({"COYOTE_SIM_", key, "_JITTER_NS"}, 0.0) * 1ns;
        retransmit = coyote_sim_env_real({"COYOTE_SIM_", key, "_RETRANSMIT_NS"}, 10000.0) * 1ns;
        if (jitter < 0) jitter = 0;
        if (retransmit < 0) retransmit = 0;
        if (gbps < 0) gbps = 0;
        bytes_per_cycle = gbps / 8.0 * (CLK_PERIOD / 1ns);

        rd = new(bytes_per_cycle);
        wr = new(bytes_per_cycle);

        mtu = $rtoi(mtu_env);
        if (mtu < 0 || mtu != mtu_env || mtu % (AXI_DATA_BITS / 8) != 0) begin
            `DEBUG(("COYOTE_SIM_%s_MTU=%0g is not a multiple of %0d B, using 0", key, mtu_env, (AXI_DATA_BITS / 8)))
            mtu = 0;
        end

        drop = coyote_sim_env_real({"COYOTE_SIM_", key, "_DROP"}, 0.0);
        if (drop < 0 || drop > 1) begin
            `DEBUG(("COYOTE_SIM_%s_DROP=%0g is not a probability, using 0", key, drop))
            drop = 0;
        end

        seed = $rtoi(coyote_sim_env_real("COYOTE_SIM_SEED", 1.0));

        `DEBUG(("%s: latency %0.0f ns, bandwidth %s, tlast %s, %s, %s", key, latency / 1ns, (gbps == 0) ? "unlimited"
            : $sformatf("%0g Gbit/s (%0.2f B/cycle)", gbps, bytes_per_cycle),
            (mtu == 0) ? "per request" : $sformatf("every %0d B", mtu),
            (jitter == 0) ? "no jitter" : $sformatf("jitter up to %0.0f ns", jitter / 1ns),
            (drop == 0) ? "no drop" : $sformatf("drop %0g %% per %s, resend after %0.0f ns", drop * 100,
                (mtu == 0) ? string'("request") : string'("MTU"), retransmit / 1ns)))
    endfunction
endclass

`endif // SIM_PARAMS_SVH
