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

#ifndef CROSSOVER_HPP
#define CROSSOVER_HPP

#include "types.hpp"
#include "util.hpp"

#include <cassert>
#include <hls_streamofblocks.h>
#include <hls_stream.h>

inline void find_unsued_cities(
    IndividualAsBeats &p,
    hls::stream<BeatPacket> &out,
    StartEndData &start_end_data_unused_city_search,
    CityIndex num_cities,
    BeatIndex total_city_beats,
    ap_uint<MAX_CITIES> &taken
) {
    bool wraps_same_beat = (start_end_data_unused_city_search.start_beat == start_end_data_unused_city_search.end_beat &&
                            start_end_data_unused_city_search.start_city > start_end_data_unused_city_search.end_city);
    BeatIndex fill_beats_to_go = wraps_same_beat ? BeatIndex(total_city_beats + BeatIndex(1)) : BeatIndex(total_city_beats);

    assert(fill_beats_to_go <= HW_MAX_CITY_BEATS + 1);
    FIND_UNSED_CITIES_LOOP: for (BeatIndex step = 0; step < fill_beats_to_go; step++) {
        #pragma HLS PIPELINE II=1
        BeatProducerState out_state;

        BeatIndex read_b = (start_end_data_unused_city_search.start_beat + step);
        if (read_b >= total_city_beats) read_b -= total_city_beats;

        CityIndex c_start = (step == 0) ? start_end_data_unused_city_search.start_city : get_first_city_index();
        CityIndex c_end = (step == fill_beats_to_go - 1) ? start_end_data_unused_city_search.end_city : get_last_city_index(num_cities, read_b);

        Beat b = p[read_b];

        FIND_UNSED_CITIES_LOOP_INNER: for (CityIndex i = 0; i < HW_CITIES_PER_BEAT; i++) {
            #pragma HLS UNROLL
            City c = consume_next_city(b);

            if (i >= c_start && i <= c_end) {
                NodeId id = get_node_id(c);
                ap_uint<1> is_valid;
                is_valid = !taken[id];
                
                if (is_valid) {
                    append_city(out_state, c);
                }
            }
        }

        finalizeStream(out_state, out);
    }
}

inline void fill_up_in_circle(
    StartEndData &start_end_data_unused_city_search,
    StartEndDataWithBeats &start_end_data_with_beats0,
    StartEndDataWithBeats &start_end_data_with_beats1,
    IndividualAsBeats &p0,
    IndividualAsBeats &p1,
    IndividualAsBeats &c0,
    IndividualAsBeats &c1,
    BeatIndex total_city_beats,
    CityIndex num_cities,
    CityIndex start_idx,
    CityIndex n_cities_to_insert,
    ap_uint<MAX_CITIES> &taken0,
    ap_uint<MAX_CITIES> &taken1
) {
    #pragma HLS DATAFLOW
    hls::stream<BeatPacket> beat_stream_0;
    hls::stream<BeatPacket> beat_stream_1;

    find_unsued_cities(p1, beat_stream_0, start_end_data_unused_city_search, num_cities, total_city_beats, taken0);
    find_unsued_cities(p0, beat_stream_1, start_end_data_unused_city_search, num_cities, total_city_beats, taken1);

    stream_beats_to_individual<BEAT_STREAM_INTERVAL>(beat_stream_0, c0, start_idx, n_cities_to_insert, start_end_data_with_beats0, num_cities);
    stream_beats_to_individual<BEAT_STREAM_INTERVAL>(beat_stream_1, c1, start_idx, n_cities_to_insert, start_end_data_with_beats1, num_cities);
}

inline void crossover(
    hls::stream_of_blocks<IndividualAsBeats> &in0,
    hls::stream_of_blocks<IndividualAsBeats> &in1,
    hls::stream<CityPair> &crossover_pairs,
    hls::stream_of_blocks<IndividualAsBeats> &out0,
    hls::stream_of_blocks<IndividualAsBeats> &out1,
    int num_individuals,
    CityIndex num_cities,
    Probability crossover_prob
) {
    BeatIndex total_city_beats = get_total_city_beats(num_cities);
    CROSSOVER_INDIV_LOOP: for (int i = 0; i < num_individuals; i++) {
        hls::read_lock<IndividualAsBeats> p0(in0);
        hls::write_lock<IndividualAsBeats> c0(out0);
        hls::read_lock<IndividualAsBeats> p1(in1);
        hls::write_lock<IndividualAsBeats> c1(out1);

        CityPair cut_points = crossover_pairs.read();

        set_fitness(c0, get_fitness(p0, num_cities), num_cities);
        set_fitness(c1, get_fitness(p1, num_cities), num_cities);

        // Mark nodes already present in the slice
        ap_uint<MAX_CITIES> taken0 = 0;
        ap_uint<MAX_CITIES> taken1 = 0;

        CityIndex start_idx;
        CityIndex end_idx;
        if (cut_points.prob_rnd <= crossover_prob) {
            start_idx = cut_points.start;
            end_idx = cut_points.end;
        } else {
            start_idx = 0;
            end_idx = num_cities - 1;
        }
        StartEndData start_end_data = get_start_end_data(start_idx, end_idx);

        BeatIndex itrs = start_end_data.end_beat - start_end_data.start_beat + 1;
        assert(itrs <= HW_MAX_CITY_BEATS);
        COPY_BEAT_LOOP: for (BeatIndex i = 0; i < itrs; i++) {
            #pragma HLS PIPELINE II=1
            BeatIndex b = i + start_end_data.start_beat;
            CityIndex low_city = (b == start_end_data.start_beat) ? start_end_data.start_city : get_first_city_index();
            CityIndex high_city = (b == start_end_data.end_beat) ? start_end_data.end_city : get_last_city_index(num_cities, b);

            Beat p0b = p0[b];
            Beat p1b = p1[b];
            c0[b] = p0b;
            c1[b] = p1b;

            ap_uint<MAX_CITIES> mask0[HW_CITIES_PER_BEAT];
            #pragma HLS ARRAY_PARTITION variable=mask0 complete
            ap_uint<MAX_CITIES> mask1[HW_CITIES_PER_BEAT];
            #pragma HLS ARRAY_PARTITION variable=mask1 complete

            OX_COPY_CITY_LOOP: for (CityIndex j = 0; j < HW_CITIES_PER_BEAT; j++) {
                #pragma HLS UNROLL
                City c0_val = consume_next_city(p0b);
                City c1_val = consume_next_city(p1b);

                mask0[j] = 0;
                mask1[j] = 0;
                if (j >= low_city && j <= high_city) {
                    NodeId id0 = get_node_id(c0_val);
                    mask0[j][id0] = 1;

                    NodeId id1 = get_node_id(c1_val);
                    mask1[j][id1] = 1;
                }
            }

            OR_REDUCE: for (CityBeatIndex i = 0; i < HW_CITIES_PER_BEAT; ++i) {
                #pragma HLS UNROLL
                taken0 |= mask0[i];
                taken1 |= mask1[i];
            }
        }

        CityIndex next_city = (end_idx == num_cities - 1) ? CityIndex(0) : CityIndex(end_idx + 1);
        CityIndex prev_city = (start_idx == 0) ? CityIndex(num_cities - 1) : CityIndex(start_idx - 1);

        StartEndData start_end_data_unused_city_search = get_start_end_data(next_city, end_idx);
        StartEndData start_end_data_circle = get_start_end_data(next_city, prev_city);
        StartEndDataWithBeats start_end_data_with_beats0(start_end_data_circle, p0[start_end_data_circle.start_beat], p0[start_end_data_circle.end_beat]);
        StartEndDataWithBeats start_end_data_with_beats1(start_end_data_circle, p1[start_end_data_circle.start_beat], p1[start_end_data_circle.end_beat]);

        fill_up_in_circle(start_end_data_unused_city_search, start_end_data_with_beats0, start_end_data_with_beats1, p0, p1, c0, c1, total_city_beats, num_cities, next_city, num_cities - (end_idx - start_idx + 1), taken0, taken1);
    }
}

#endif // CROSSOVER_HPP
