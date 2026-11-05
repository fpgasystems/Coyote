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

#ifndef TWO_OPT_HPP
#define TWO_OPT_HPP

#include "types.hpp"
#include "util.hpp"
#include "xoroshiro128plusplus.hpp"
#include <hls_streamofblocks.h>
#include <hls_stream.h>

#ifndef N_TWO_OPT_WORKERS
#define N_TWO_OPT_WORKERS 2
#endif

struct SubtourMeta {
    CityIndex length;
    Fitness delta;
    bool last_of_indiv;
    bool last_of_batch;
};

static inline bool evaluate_interval_step(
    Point prev_coord_left,
    Point curr_coord_left,
    Point curr_coord_right,
    Point prev_coord_right,
    Fitness &d_old,
    Fitness &d_new
) {
    #pragma HLS INLINE
    Fitness d_old_left  = floored_distance(prev_coord_left, curr_coord_left);
    Fitness d_old_right = floored_distance(curr_coord_right, prev_coord_right);
    Fitness d_new_left  = floored_distance(prev_coord_left, curr_coord_right);
    Fitness d_new_right = floored_distance(curr_coord_left, prev_coord_right);

    d_old = d_old_left + d_old_right;
    d_new = d_new_left + d_new_right;
    return (d_old > d_new);
}

static inline bool evaluate_interval_step_pipelined(
    Point prev_coord_left,
    Point curr_coord_left,
    Point curr_coord_right,
    Point prev_coord_right,
    Fitness &d_old,
    Fitness &d_new
) {
    #pragma HLS INLINE

    Point pts_a[4] = {prev_coord_left, curr_coord_right, prev_coord_left, curr_coord_left};
    Point pts_b[4] = {curr_coord_left, prev_coord_right, curr_coord_right, prev_coord_right};
    #pragma HLS ARRAY_PARTITION variable=pts_a complete
    #pragma HLS ARRAY_PARTITION variable=pts_b complete

    Fitness dists[4];
    #pragma HLS ARRAY_PARTITION variable=dists complete

    PRECHECK_DIST_LOOP: for (int d = 0; d < 4; ++d) {
        #pragma HLS PIPELINE II=1
        dists[d] = floored_distance(pts_a[d], pts_b[d]);
    }

    Fitness d_old_left  = dists[0];
    Fitness d_old_right = dists[1];
    Fitness d_new_left  = dists[2];
    Fitness d_new_right = dists[3];

    d_old = d_old_left + d_old_right;
    d_new = d_new_left + d_new_right;
    return (d_old > d_new);
}

inline void symmetric_sweep(
    NodeId tour_buf[MAX_CITIES],
    const CityData city_cache[MAX_CACHE_ENTRIES],
    CityIndex start, CityIndex end,
    CityIndex L, CityIndex R,
    NodeId DEPOT,
    Fitness &sweep_delta,
    bool enable_precheck
) {
    CityIndex M = (R - L + 1) / 2;
    Fitness local_delta = 0;
    bool swap_flag = false;

    NodeId prev_node_left  = (L == start) ? DEPOT : tour_buf[L - 1];
    NodeId prev_node_right = (R == end)   ? DEPOT : tour_buf[R + 1];

    Point prev_coord_left  = get_coord(city_cache[prev_node_left]);
    Point prev_coord_right = get_coord(city_cache[prev_node_right]);

    if (enable_precheck) {
        NodeId curr_node_left0  = tour_buf[L];
        NodeId curr_node_right0 = tour_buf[R];
        Point curr_coord_left0  = get_coord(city_cache[curr_node_left0]);
        Point curr_coord_right0 = get_coord(city_cache[curr_node_right0]);

        Fitness d_old0, d_new0;
        bool imp0 = evaluate_interval_step_pipelined(
            prev_coord_left,
            curr_coord_left0,
            curr_coord_right0,
            prev_coord_right,
            d_old0,
            d_new0
        );

        if (!imp0) {
            sweep_delta = 0;
            return;
        }
    }

    bool improves[MAX_CITIES / 2];
    NodeId tmp_left[MAX_CITIES / 2];
    NodeId tmp_right[MAX_CITIES / 2];

    EVAL_LOOP: for (CityIndex i = 0; i < M; ++i) {
        #pragma HLS PIPELINE II=1

        NodeId curr_node_left  = tour_buf[L + i];
        NodeId curr_node_right = tour_buf[R - i];
        tmp_left[i]  = curr_node_left;
        tmp_right[i] = curr_node_right;
        Point curr_coord_left  = get_coord(city_cache[curr_node_left]);
        Point curr_coord_right = get_coord(city_cache[curr_node_right]);

        Fitness d_old, d_new;
        bool imp = evaluate_interval_step(
            prev_coord_left,
            curr_coord_left,
            curr_coord_right,
            prev_coord_right,
            d_old,
            d_new
        );
        improves[i] = imp;

        if (imp) {
            local_delta += (d_old - d_new);
        }

        prev_coord_left  = curr_coord_left;
        prev_coord_right = curr_coord_right;
    }

    APPLY_LOOP: for (CityIndex i = 0; i < M; ++i) {
        #pragma HLS PIPELINE II=1
        #pragma HLS DEPENDENCE variable=tour_buf inter false

        swap_flag ^= improves[i];

        if (swap_flag) {
            NodeId curr_node_left  = tmp_left[i];
            NodeId curr_node_right = tmp_right[i];
            tour_buf[L + i] = curr_node_right;
            tour_buf[R - i] = curr_node_left;
        }
    }

    sweep_delta = local_delta;
}

inline void two_opt_worker(
    hls::stream<SubtourMeta> &meta_in,
    hls::stream<NodeId>      &cities_in,
    hls::stream<SubtourMeta> &meta_out,
    hls::stream<NodeId>      &cities_out,
    CityIndex num_cities,
    CityIndex two_opt_k,
    bool enable_precheck,
    const CityData city_cache[MAX_CACHE_ENTRIES],
    xoroshiro128plusplus &rng,
    uint32_t seed_worker
) {
    rng.init(seed_worker);

    NodeId local_tour[MAX_CITIES];
    bool batch_done = false;

    OPTIMIZE_SUBTOURS_LOOP: while (!batch_done) {
        SubtourMeta meta = meta_in.read();
        batch_done = meta.last_of_batch;

        if (batch_done) {
            break;
        }

        CityIndex len = meta.length;
        Fitness subtour_delta = 0;

        LOAD_TOUR_LOOP: for (CityIndex i = 0; i < len; ++i) {
            #pragma HLS PIPELINE II=1
            local_tour[i] = cities_in.read();
        }

        if (len > 0) {
            MOVE_LOOP: for (CityIndex move = 0; move < two_opt_k; ++move) {
                uint32_t r1, r2;
                rng.nextPair(len, r1, r2);

                if (len >= 3) {
                    CityIndex L_rel = r1;
                    CityIndex R_rel = r2;

                    if (L_rel > R_rel) {
                        CityIndex tmp = L_rel;
                        L_rel = R_rel;
                        R_rel = tmp;
                    }

                    if (L_rel != R_rel) {
                        Fitness sweep_delta = 0;
                        symmetric_sweep(
                            local_tour,
                            city_cache,
                            0, len - 1,
                            L_rel, R_rel,
                            num_cities,
                            sweep_delta,
                            enable_precheck
                        );
                        subtour_delta += sweep_delta;
                    }
                }
            }
        }

        meta_out.write(SubtourMeta{len, subtour_delta, meta.last_of_indiv, false});

        EMIT_TOUR_LOOP: for (CityIndex i = 0; i < len; ++i) {
            #pragma HLS PIPELINE II=1
            cities_out.write(local_tour[i]);
        }
    }
}

inline void extract_subtours(
    hls::stream_of_blocks<IndividualAsBeats> &in,
    int num_individuals,
    CityIndex num_cities,
    hls::stream<SubtourMeta> &meta_stream,
    hls::stream<NodeId>      &city_stream,
    hls::stream<Fitness>     &fitness_stream
) {
    EXTRACT_INDIV_LOOP: for (int indiv = 0; indiv < num_individuals; ++indiv) {
        hls::read_lock<IndividualAsBeats> in_ind(in);

        Fitness old_fitness = get_fitness(in_ind, num_cities);
        fitness_stream.write(old_fitness);

        Beat active_beat = in_ind[0];
        CityBeatIndex cities_in_beat = HW_CITIES_PER_BEAT;
        BeatIndex beat_idx = 0;

        CityIndex total_cities_read = 0;
        bool indiv_done = false;

        EXTRACT_SUBTOURS_LOOP: while (!indiv_done) {
            CityIndex tour_len = 0;
            bool subtour_done = false;

            BUILD_TOUR_LOOP: while (!subtour_done) {
                #pragma HLS PIPELINE II=1

                City current_city = active_beat.range(CITY_BITS - 1, 0);
                NodeId nid = get_node_id(current_city);
                bool is_depot = get_is_depot(current_city);

                city_stream.write(nid);
                tour_len++;
                total_cities_read++;

                if (is_depot) {
                    subtour_done = true;
                }
                if (total_cities_read == num_cities) {
                    subtour_done = true;
                    indiv_done = true;
                }

                if (cities_in_beat == 1) {
                    beat_idx++;
                    if (total_cities_read < num_cities) {
                        active_beat = in_ind[beat_idx];
                    }
                    cities_in_beat = HW_CITIES_PER_BEAT;
                } else {
                    active_beat >>= CITY_BITS;
                    cities_in_beat--;
                }
            }

            meta_stream.write(SubtourMeta{tour_len, 0, indiv_done, false});
        }
    }
}

inline void forward_subtour_cities(
    hls::stream<NodeId> &cities_in,
    hls::stream<NodeId> &worker_cities,
    CityIndex length
) {
    FORWARD_CITIES_LOOP: for (CityIndex i = 0; i < length; ++i) {
        #pragma HLS PIPELINE II=1
        worker_cities.write(cities_in.read());
    }
}

template <int N_WORKERS>
void dispatch_subtours(
    hls::stream<SubtourMeta> &meta_in,
    hls::stream<NodeId>      &cities_in,
    int num_individuals,
    hls::stream<SubtourMeta> (&worker_meta)[N_WORKERS],
    hls::stream<NodeId>      (&worker_cities)[N_WORKERS]
) {
    int worker_idx = 0;

    DISPATCH_INDIV_LOOP: for (int indiv = 0; indiv < num_individuals; ++indiv) {
        bool indiv_done = false;

        DISPATCH_SUBTOURS_LOOP: while (!indiv_done) {
            SubtourMeta meta = meta_in.read();
            indiv_done = meta.last_of_indiv;

            int w = worker_idx;
            worker_idx = (worker_idx == N_WORKERS - 1) ? 0 : (worker_idx + 1);

            worker_meta[w].write(meta);
            forward_subtour_cities(cities_in, worker_cities[w], meta.length);
        }
    }

    TERMINATE_WORKERS_LOOP: for (int w = 0; w < N_WORKERS; ++w) {
        #pragma HLS UNROLL
        worker_meta[w].write(SubtourMeta{0, 0, false, true});
    }
}

template <int N_WORKERS>
void read_subtour_to_beats(
    int target_worker,
    hls::stream<SubtourMeta> (&worker_opt_meta)[N_WORKERS],
    hls::stream<NodeId>      (&worker_opt_cities)[N_WORKERS],
    BeatProducerState &state,
    hls::stream<BeatPacket> &beat_stream,
    Fitness &indiv_delta,
    bool &indiv_done
) {
    #pragma HLS INLINE
    DISPATCH_READ_LOOP: for (int w = 0; w < N_WORKERS; ++w) {
        #pragma HLS UNROLL
        if (target_worker == w) {
            SubtourMeta meta = worker_opt_meta[w].read();
            CityIndex len = meta.length;
            indiv_done = meta.last_of_indiv;
            indiv_delta += meta.delta;

            REBUILD_TOUR_LOOP: for (CityIndex i = 0; i < len; ++i) {
                #pragma HLS PIPELINE II=1
                NodeId nid = worker_opt_cities[w].read();
                City city = 0;
                set_node_id(city, nid);
                set_is_depot(city, (i == len - 1));
                send_city(state, city, beat_stream);
            }
        }
    }
}

template <int N_WORKERS>
void array_to_beats_all(
    hls::stream<SubtourMeta> (&worker_opt_meta)[N_WORKERS],
    hls::stream<NodeId>      (&worker_opt_cities)[N_WORKERS],
    hls::stream<BeatPacket> &beat_stream,
    hls::stream<Fitness> &delta_stream,
    int num_individuals
) {
    int worker_idx = 0;

    ARRAY_TO_BEATS_INDIV_LOOP: for (int indiv = 0; indiv < num_individuals; ++indiv) {
        BeatProducerState state;
        Fitness indiv_delta = 0;
        bool indiv_done = false;

        REBUILD_SUBTOURS_LOOP: while (!indiv_done) {
            read_subtour_to_beats<N_WORKERS>(
                worker_idx, worker_opt_meta, worker_opt_cities,
                state, beat_stream, indiv_delta, indiv_done
            );
            worker_idx = (worker_idx == N_WORKERS - 1) ? 0 : (worker_idx + 1);
        }

        finalizeStream(state, beat_stream);
        delta_stream.write(indiv_delta);
    }
}

inline void stream_beats_to_all_individuals(
    hls::stream<BeatPacket> &beat_stream,
    hls::stream<Fitness> &fitness_stream,
    hls::stream<Fitness> &delta_stream,
    hls::stream_of_blocks<IndividualAsBeats> &out,
    int num_individuals,
    CityIndex num_cities
) {
    StartEndData se = get_start_end_data(0, num_cities - 1);
    StartEndDataWithBeats se_wb(se, 0, 0);

    STREAM_BEATS_INDIV_LOOP: for (int indiv = 0; indiv < num_individuals; ++indiv) {
        hls::write_lock<IndividualAsBeats> out_ind(out);

        stream_beats_to_individual<BEAT_STREAM_INTERVAL>(
            beat_stream, out_ind, 0, num_cities, se_wb, num_cities
        );

        Fitness old_fitness = fitness_stream.read();
        Fitness total_delta = delta_stream.read();
        set_fitness(out_ind, old_fitness - total_delta, num_cities);
    }
}

inline void init_local_cache(
    const CityData city_cache[MAX_CACHE_ENTRIES],
    CityData local_cache[N_TWO_OPT_WORKERS][MAX_CACHE_ENTRIES]
) {
    INIT_CACHE_ENTRIES: for (int c = 0; c < MAX_CACHE_ENTRIES; ++c) {
        #pragma HLS PIPELINE II=1
        CityData d = city_cache[c];
        INIT_CACHE_WORKERS: for (int w = 0; w < N_TWO_OPT_WORKERS; ++w) {
            #pragma HLS UNROLL
            local_cache[w][c] = d;
        }
    }
}

inline void two_opt_streaming(
    hls::stream_of_blocks<IndividualAsBeats> &in,
    hls::stream_of_blocks<IndividualAsBeats> &out,
    int num_individuals,
    CityIndex num_cities,
    CityIndex two_opt_k,
    bool enable_precheck,
    const CityData local_cache[N_TWO_OPT_WORKERS][MAX_CACHE_ENTRIES],
    uint32_t seed_two_opt
) {
    #pragma HLS DATAFLOW

    hls::stream<SubtourMeta> meta_stream;
    #pragma HLS STREAM variable=meta_stream depth=4
    hls::stream<NodeId>      city_stream;
    #pragma HLS STREAM variable=city_stream depth=MAX_CITIES

    hls::stream<SubtourMeta> worker_meta[N_TWO_OPT_WORKERS];
    #pragma HLS STREAM variable=worker_meta depth=4
    hls::stream<NodeId>      worker_cities[N_TWO_OPT_WORKERS];
    #pragma HLS STREAM variable=worker_cities depth=MAX_CITIES
    hls::stream<SubtourMeta> worker_opt_meta[N_TWO_OPT_WORKERS];
    #pragma HLS STREAM variable=worker_opt_meta depth=4
    hls::stream<NodeId>      worker_opt_cities[N_TWO_OPT_WORKERS];
    #pragma HLS STREAM variable=worker_opt_cities depth=MAX_CITIES
    xoroshiro128plusplus worker_rng[N_TWO_OPT_WORKERS];
    #pragma HLS ARRAY_PARTITION variable=worker_rng complete dim=1

    hls::stream<BeatPacket>  beat_stream;
    #pragma HLS STREAM variable=beat_stream depth=16
    hls::stream<Fitness>     fitness_stream;
    #pragma HLS STREAM variable=fitness_stream depth=8
    hls::stream<Fitness>     delta_stream;
    #pragma HLS STREAM variable=delta_stream depth=2

    extract_subtours(
        in, num_individuals, num_cities,
        meta_stream, city_stream, fitness_stream
    );

    dispatch_subtours<N_TWO_OPT_WORKERS>(
        meta_stream, city_stream,
        num_individuals,
        worker_meta, worker_cities
    );

    TWO_OPT_WORKERS_LOOP: for (int w = 0; w < N_TWO_OPT_WORKERS; ++w) {
        #pragma HLS UNROLL
        two_opt_worker(
            worker_meta[w], worker_cities[w],
            worker_opt_meta[w], worker_opt_cities[w],
            num_cities, two_opt_k,
            enable_precheck,
            local_cache[w],
            worker_rng[w],
            seed_two_opt ^ (static_cast<uint32_t>(w) * 0x9E3779B9u)
        );
    }

    array_to_beats_all<N_TWO_OPT_WORKERS>(
        worker_opt_meta, worker_opt_cities,
        beat_stream, delta_stream,
        num_individuals
    );

    stream_beats_to_all_individuals(
        beat_stream, fitness_stream, delta_stream, out,
        num_individuals, num_cities
    );
}

inline void two_opt(
    hls::stream_of_blocks<IndividualAsBeats> &in,
    hls::stream_of_blocks<IndividualAsBeats> &out,
    int num_individuals,
    CityIndex num_cities,
    CityIndex two_opt_k,
    bool enable_precheck,
    const CityData city_cache[MAX_CACHE_ENTRIES],
    uint32_t seed_two_opt
) {
    CityData local_cache[N_TWO_OPT_WORKERS][MAX_CACHE_ENTRIES];
    #pragma HLS ARRAY_PARTITION variable=local_cache complete dim=1
    #pragma HLS BIND_STORAGE variable=local_cache type=ram_t2p impl=bram

    init_local_cache(city_cache, local_cache);

    two_opt_streaming(
        in, out,
        num_individuals, num_cities, two_opt_k,
        enable_precheck,
        local_cache,
        seed_two_opt
    );
}

#endif // TWO_OPT_HPP
