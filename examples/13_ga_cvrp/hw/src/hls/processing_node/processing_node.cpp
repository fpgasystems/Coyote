/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2026, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#include "processing_node.hpp"
#include "crossover.hpp"
#include "mutate.hpp"
#include "repair_fitness.hpp"
#include "two_opt.hpp"
#include <hls_streamofblocks.h>


static inline Beat consume_next_hw_beat(
    hls::stream<axi_word_t> &in_stream,
    AxiBeat &current_beat,
    BeatAxiIndex &beats_left
) {
    #pragma HLS INLINE
    if (beats_left == 0) {
        axi_word_t word = in_stream.read();
        current_beat = word.data;
        beats_left = HW_BEATS_PER_AXI_BEAT - 1;
    } else {
        beats_left--;
    }
    return consume_next_hw_beat(current_beat);
}

static void producer(
    hls::stream<axi_word_t> &in_stream,
    hls::stream_of_blocks<IndividualAsBeats> &out,
    int num_individuals,
    CityIndex num_cities
) {
    BeatIndex total_hw_city_beats = get_total_city_beats(num_cities);

    PRODUCER_INDIV_LOOP: for (int i = 0; i < num_individuals; i++) {
        hls::write_lock<IndividualAsBeats> ind(out);

        AxiBeat current_beat = 0;
        BeatAxiIndex beats_left = 0;

        DECODE_CITY_BEATS: for (BeatIndex b = 0; b < total_hw_city_beats; b++) {
            #pragma HLS PIPELINE II=1
            ind[b] = consume_next_hw_beat(in_stream, current_beat, beats_left);
        }

        // Consume dedicated fitness beat
        beats_left = 0;
        ind[total_hw_city_beats] = consume_next_hw_beat(in_stream, current_beat, beats_left);
    }
}

static void consumer(
    hls::stream_of_blocks<IndividualAsBeats> &in,
    hls::stream<axi_word_t> &out_stream,
    int num_individuals,
    CityIndex num_cities
) {
    BeatIndex total_hw_city_beats = get_total_city_beats(num_cities);

    CONSUMER_INDIV_LOOP: for (int i = 0; i < num_individuals; i++) {
        hls::read_lock<IndividualAsBeats> ind(in);

        axi_word_t word;
        word.data = 0;
        word.keep = -1;
        word.strb = -1;
        word.last = 0;

        BeatAxiIndex beat_cnt = 0;
        ENCODE_CITY_BEATS: for (BeatIndex b = 0; b < total_hw_city_beats; b++) {
            #pragma HLS PIPELINE II=1
            word.data >>= HW_BEAT_WIDTH;
            word.data.range(AXI_BEAT_WIDTH - 1, AXI_BEAT_WIDTH - HW_BEAT_WIDTH) = ind[b];
            beat_cnt++;

            if (beat_cnt == HW_BEATS_PER_AXI_BEAT) {
                out_stream.write(word);
                word.data = 0;
                beat_cnt = 0;
            }
        }

        // If the last AXI beat is partially filled, right-align it to LSB and flush
        if (beat_cnt != 0) {
            word.data >>= (HW_BEATS_PER_AXI_BEAT - beat_cnt) * HW_BEAT_WIDTH;
            out_stream.write(word);
        }

        // Dedicated fitness beat
        axi_word_t fit_word;
        fit_word.data = 0;
        fit_word.data.range(HW_BEAT_WIDTH - 1, 0) = ind[total_hw_city_beats];
        fit_word.keep = -1;
        fit_word.strb = -1;
        fit_word.last = (i == num_individuals - 1) ? 1 : 0;
        out_stream.write(fit_word);
    }
}

static void generate_random_city_indices(
    uint32_t seed_cx_mut,
    hls::stream<CityPair> &random_city_pairs,
    int num_individuals,
    CityIndex num_cities
) {
    #pragma HLS INLINE off
    static xoroshiro128plusplus rng;
    rng.init(seed_cx_mut);

    int total_steps = num_individuals * 9;
    ap_uint<2> step = 0;
    Probability rnd_prob = 0;
    CityIndex rnd0 = 0;

    RAND_GEN_LOOP: for (int i = 0; i < total_steps; ++i) {
        #pragma HLS PIPELINE II=1
        uint32_t bound = (step == 0) ? 100 : static_cast<uint32_t>(num_cities);
        uint32_t rnd = rng.nextUInt(bound);

        switch (step) {
            case 0:
                rnd_prob = rnd + 1;
                step = 1;
                break;
            case 1:
                rnd0 = rnd;
                step = 2;
                break;
            case 2: {
                CityIndex rnd1 = rnd;
                CityPair pair;
                if (rnd0 <= rnd1) {
                    pair.start = rnd0;
                    pair.end = rnd1;
                } else {
                    pair.start = rnd1;
                    pair.end = rnd0;
                }
                pair.prob_rnd = rnd_prob;
                random_city_pairs.write(pair);
                step = 0;
                break;
            }
            default:
                step = 0;
                break;
        }
    }
}

static void form_city_pairs(
    hls::stream<CityPair> &random_city_pairs,
    hls::stream<CityPair> &crossover_pairs,
    hls::stream<CityPair> &mutate_pairs_0,
    hls::stream<CityPair> &mutate_pairs_1,
    int num_individuals
) {
    FORM_PAIRS_LOOP: for (int indiv = 0; indiv < num_individuals; ++indiv) {
        #pragma HLS PIPELINE II=3
        CityPair cx_pair   = random_city_pairs.read();
        CityPair mut_pair0 = random_city_pairs.read();
        CityPair mut_pair1 = random_city_pairs.read();

        crossover_pairs.write(cx_pair);
        mutate_pairs_0.write(mut_pair0);
        mutate_pairs_1.write(mut_pair1);
    }
}

void generate_cx_mut_randoms(
    uint32_t seed_cx_mut,
    hls::stream<CityPair> &crossover_pairs,
    hls::stream<CityPair> &mutate_pairs_0,
    hls::stream<CityPair> &mutate_pairs_1,
    int num_individuals,
    CityIndex num_cities
) {
    #pragma HLS DATAFLOW

    hls::stream<CityPair> random_city_pairs;
    #pragma HLS STREAM variable=random_city_pairs depth=16
    generate_random_city_indices(seed_cx_mut, random_city_pairs, num_individuals, num_cities);
    form_city_pairs(random_city_pairs, crossover_pairs, mutate_pairs_0, mutate_pairs_1, num_individuals);
}

static inline CityData consume_next_city_data(
    hls::stream<axi_word_t> &in0,
    CityCacheBeat &current_beat,
    BeatCacheIndex &words_left
) {
    #pragma HLS INLINE
    if (words_left == 0) {
        axi_word_t word = in0.read();
        current_beat = word.data;
        words_left = NODE_CACHE_ENTRIES_PER_BEAT - 1;
    } else {
        words_left--;
    }
    return consume_next_city_data(current_beat);
}

static CityData cache_0[MAX_CACHE_ENTRIES];
static CityData cache_1[MAX_CACHE_ENTRIES];
static CityData cache_2opt_0[MAX_CACHE_ENTRIES];
static CityData cache_2opt_1[MAX_CACHE_ENTRIES];

static void init_node_cache(
    hls::stream<axi_word_t> &in0,
    int num_cities
) {
    #pragma HLS BIND_STORAGE variable=cache_0 type=ram_1p impl=bram
    #pragma HLS BIND_STORAGE variable=cache_1 type=ram_1p impl=bram
    #pragma HLS BIND_STORAGE variable=cache_2opt_0 type=ram_2p impl=bram
    #pragma HLS BIND_STORAGE variable=cache_2opt_1 type=ram_2p impl=bram
    CityCacheBeat current_beat = 0;
    BeatCacheIndex words_left = 0;
    int total_entries = num_cities + 1;

    INIT_CACHE_LOOP: for (int city_idx = 0; city_idx < total_entries; ++city_idx) {
        #pragma HLS PIPELINE II=1
        CityData cd = consume_next_city_data(in0, current_beat, words_left);
        cache_0[city_idx] = cd;
        cache_1[city_idx] = cd;
        cache_2opt_0[city_idx] = cd;
        cache_2opt_1[city_idx] = cd;
    }
}

static void process_stream(
    hls::stream<axi_word_t> &in0,
    hls::stream<axi_word_t> &out0,
    hls::stream<axi_word_t> &in1,
    hls::stream<axi_word_t> &out1,
    int num_individuals,
    CityIndex num_cities,
    Capacity vehicle_capacity,
    CityIndex two_opt_k,
    bool two_opt_enable_precheck,
    uint32_t seed_cx_mut,
    uint32_t seed_two_opt0,
    uint32_t seed_two_opt1,
    Probability crossover_prob,
    Probability mutation_prob
) {
    #pragma HLS DATAFLOW

    hls::stream_of_blocks<IndividualAsBeats> stream_0;
    hls::stream_of_blocks<IndividualAsBeats> stream_1;
    hls::stream_of_blocks<IndividualAsBeats> stream_cx_0;
    hls::stream_of_blocks<IndividualAsBeats> stream_cx_1;
    hls::stream_of_blocks<IndividualAsBeats> stream_mut_0;
    hls::stream_of_blocks<IndividualAsBeats> stream_mut_1;
    hls::stream_of_blocks<IndividualAsBeats> stream_repaired_0;
    hls::stream_of_blocks<IndividualAsBeats> stream_repaired_1;
    hls::stream_of_blocks<IndividualAsBeats> stream_opt_0;
    hls::stream_of_blocks<IndividualAsBeats> stream_opt_1;

    #pragma HLS BIND_STORAGE variable=stream_cx_0       type=ram_2p impl=bram latency=2
    #pragma HLS BIND_STORAGE variable=stream_cx_1       type=ram_2p impl=bram latency=2
    #pragma HLS BIND_STORAGE variable=stream_repaired_0 type=ram_2p impl=bram latency=2
    #pragma HLS BIND_STORAGE variable=stream_repaired_1 type=ram_2p impl=bram latency=2
    #pragma HLS BIND_STORAGE variable=stream_mut_0      type=ram_2p impl=bram latency=2
    #pragma HLS BIND_STORAGE variable=stream_mut_1      type=ram_2p impl=bram latency=2
    #pragma HLS BIND_STORAGE variable=stream_opt_0      type=ram_2p impl=bram latency=2
    #pragma HLS BIND_STORAGE variable=stream_opt_1      type=ram_2p impl=bram latency=2
    #pragma HLS BIND_STORAGE variable=stream_0          type=ram_2p impl=bram latency=2
    #pragma HLS BIND_STORAGE variable=stream_1          type=ram_2p impl=bram latency=2

    hls::stream<CityPair> crossover_pairs;
    hls::stream<CityPair> mutate_pairs_0;
    hls::stream<CityPair> mutate_pairs_1;

    producer(in0, stream_0, num_individuals, num_cities);
    producer(in1, stream_1, num_individuals, num_cities);
    generate_cx_mut_randoms(seed_cx_mut, crossover_pairs, mutate_pairs_0, mutate_pairs_1, num_individuals, num_cities);
    crossover(stream_0, stream_1, crossover_pairs, stream_cx_0, stream_cx_1, num_individuals, num_cities, crossover_prob);
    mutate(stream_cx_0, mutate_pairs_0, stream_mut_0, num_individuals, num_cities, mutation_prob);
    mutate(stream_cx_1, mutate_pairs_1, stream_mut_1, num_individuals, num_cities, mutation_prob);
    repair_fitness(stream_mut_0, stream_repaired_0, num_individuals, num_cities, vehicle_capacity, cache_0);
    repair_fitness(stream_mut_1, stream_repaired_1, num_individuals, num_cities, vehicle_capacity, cache_1);
    two_opt(stream_repaired_0, stream_opt_0, num_individuals, num_cities, two_opt_k, two_opt_enable_precheck, cache_2opt_0, seed_two_opt0);
    two_opt(stream_repaired_1, stream_opt_1, num_individuals, num_cities, two_opt_k, two_opt_enable_precheck, cache_2opt_1, seed_two_opt1);
    consumer(stream_opt_0, out0, num_individuals, num_cities);
    consumer(stream_opt_1, out1, num_individuals, num_cities);
}

void processing_node(
    hls::stream<axi_word_t> &in0,
    hls::stream<axi_word_t> &out0,
    hls::stream<axi_word_t> &in1,
    hls::stream<axi_word_t> &out1,
    int num_individuals,
    int num_cities,
    int vehicle_capacity,
    int init_city_cache,
    int two_opt_k,
    int two_opt_enable_precheck,
    uint32_t seed,
    int crossover_prob,
    int mutation_prob
) {
    #pragma HLS INTERFACE axis port=in0
    #pragma HLS INTERFACE axis port=out0
    #pragma HLS INTERFACE axis port=in1
    #pragma HLS INTERFACE axis port=out1

    #pragma HLS INTERFACE s_axilite port=num_individuals offset=0x10 bundle=control
    #pragma HLS INTERFACE s_axilite port=num_cities offset=0x18 bundle=control
    #pragma HLS INTERFACE s_axilite port=vehicle_capacity offset=0x20 bundle=control
    #pragma HLS INTERFACE s_axilite port=init_city_cache offset=0x28 bundle=control
    #pragma HLS INTERFACE s_axilite port=two_opt_k offset=0x30 bundle=control
    #pragma HLS INTERFACE s_axilite port=two_opt_enable_precheck offset=0x38 bundle=control
    #pragma HLS INTERFACE s_axilite port=seed offset=0x40 bundle=control
    #pragma HLS INTERFACE s_axilite port=crossover_prob offset=0x48 bundle=control
    #pragma HLS INTERFACE s_axilite port=mutation_prob offset=0x50 bundle=control

    #pragma HLS INTERFACE s_axilite port=return bundle=control

    if (init_city_cache) {
        init_node_cache(in0, num_cities);
    } else {
        uint32_t seed_cx_mut   = seed;
        uint32_t seed_two_opt0 = seed ^ 0x55555555u;
        uint32_t seed_two_opt1 = seed ^ 0xAAAAAAAAu;
        process_stream(in0, out0, in1, out1, num_individuals, CityIndex(num_cities), Capacity(vehicle_capacity), CityIndex(two_opt_k), bool(two_opt_enable_precheck != 0), seed_cx_mut, seed_two_opt0, seed_two_opt1, Probability(crossover_prob), Probability(mutation_prob));
    }
}
