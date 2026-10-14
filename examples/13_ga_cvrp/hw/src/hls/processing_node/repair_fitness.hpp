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

#ifndef REPAIR_FITNESS_HPP
#define REPAIR_FITNESS_HPP

#include "types.hpp"
#include "util.hpp"

#include <cassert>
#include <hls_streamofblocks.h>
#include <hls_stream.h>

// Static mask to clear all depot flags
static inline ap_uint<HW_BEAT_WIDTH> get_clear_depots_mask() {
    #pragma HLS INLINE
    ap_uint<HW_BEAT_WIDTH> mask = ~(ap_uint<HW_BEAT_WIDTH>(0));
    for (int i = 0; i < HW_CITIES_PER_BEAT; ++i) {
        #pragma HLS UNROLL
        // Clear the specific depot bit for each city
        mask &= ~(ap_uint<HW_BEAT_WIDTH>(1) << (i * CITY_BITS + DEPOT_FLAG_OFFSET));
    }
    return mask;
}

inline void stream_coord(
    hls::stream<CoordElement> &coords,
    Point coord,
    bool is_depot,
    bool last
) {
    #pragma HLS INLINE
    CoordElement elem;
    elem.coord = coord;
    elem.is_depot = is_depot;
    elem.last = last;
    coords.write(elem);
}

inline void stream_input_beats(
    const IndividualAsBeats &input,
    BeatIndex total_beats,
    hls::stream<Beat> &input_beats
) {
    const ap_uint<HW_BEAT_WIDTH> CLEAR_DEPOT_MASK = get_clear_depots_mask();
    STREAM_INPUT_BEATS_LOOP: for (BeatIndex b = 0; b < total_beats; ++b) {
        #pragma HLS PIPELINE II=1
        input_beats.write(input[b] & CLEAR_DEPOT_MASK);
    }
}

inline void create_city_stream(
    hls::stream<Beat> &input_beats,
    CityIndex num_cities,
    const CityData city_cache[MAX_CACHE_ENTRIES],
    hls::stream<CityElement> &city_stream
) {
    Beat active_beat = input_beats.read();
    CityBeatIndex cities_in_beat = HW_CITIES_PER_BEAT;

    CREATE_CITIES_LOOP: for (CityIndex city_idx = 0; city_idx < num_cities; ++city_idx) {
        #pragma HLS PIPELINE II=1

        City current_city = active_beat.range(CITY_BITS - 1, 0);
        NodeId current_node = get_node_id(current_city);
        CityData cdata = city_cache[current_node];
        Point coord = get_coord(cdata);

        CityElement elem;
        elem.city = current_city;
        elem.demand = cdata.demand;
        elem.coord = coord;
        city_stream.write(elem);

        if (cities_in_beat == 1) {
            if (city_idx + 1 < num_cities) {
                active_beat = input_beats.read();
            }
            cities_in_beat = HW_CITIES_PER_BEAT;
        } else {
            active_beat >>= CITY_BITS;
            cities_in_beat--;
        }
    }
}

inline void repair_depots(
    hls::stream<CityElement> &city_stream,
    CityIndex num_cities,
    Capacity vehicle_capacity,
    hls::stream<CoordElement> &coords,
    hls::stream<BeatPacket> &beat_stream
) {
    BeatProducerState out_state;

    CityElement first_elem = city_stream.read();
    City prev_city = first_elem.city;
    Point prev_coord = first_elem.coord;
    Capacity remaining_capacity = vehicle_capacity - first_elem.demand;

    assert(num_cities <= MAX_CITIES);
    REPAIR_CITY_LOOP: for (CityIndex city_idx = 1; city_idx < num_cities; ++city_idx) {
        #pragma HLS PIPELINE II=1

        CityElement elem = city_stream.read();

        bool route_exceeds = (elem.demand > remaining_capacity);

        if (route_exceeds) {
            set_is_depot(prev_city, true);
            stream_coord(coords, prev_coord, true, false);
            remaining_capacity = vehicle_capacity - elem.demand;
        } else {
            stream_coord(coords, prev_coord, false, false);
            remaining_capacity -= elem.demand;
        }

        send_city(out_state, prev_city, beat_stream);

        prev_city = elem.city;
        prev_coord = elem.coord;
    }

    // Finalize end of individual
    set_is_depot(prev_city, true);
    stream_coord(coords, prev_coord, true, true);

    send_city(out_state, prev_city, beat_stream);
    finalizeStream(out_state, beat_stream);
}

inline Fitness calculate_fitness(
    hls::stream<CoordElement> &coords,
    Point depot_coord,
    CityIndex num_cities
) {
    Fitness total = 0;
    Point prev_coord = depot_coord;

    assert(num_cities <= MAX_CITIES);
    CONSUME_COORDS_LOOP: for (CityIndex i = 0; i < num_cities; ++i) {
        #pragma HLS PIPELINE II=1
        CoordElement elem = coords.read();
        Fitness d1 = floored_distance(prev_coord, elem.coord);
        Fitness d2 = floored_distance(elem.coord, depot_coord);
        total += d1;
        if (elem.is_depot) {
            total += d2;
            prev_coord = depot_coord;
        } else {
            prev_coord = elem.coord;
        }
    }

    return total;
}

inline void repair_and_calculate(
    const IndividualAsBeats &input,
    IndividualAsBeats &output,
    CityIndex num_cities,
    BeatIndex total_city_beats,
    Capacity vehicle_capacity,
    const CityData city_cache[MAX_CACHE_ENTRIES],
    Point depot_coord,
    Fitness &fitness,
    const StartEndDataWithBeats &start_end_data
) {
    #pragma HLS DATAFLOW
    hls::stream<Beat> input_beats("input_beats");
    hls::stream<CityElement> city_stream("city_stream");
    hls::stream<CoordElement> coords("coords");
    hls::stream<BeatPacket> beat_stream("beat_stream");

    stream_input_beats(input, total_city_beats, input_beats);
    create_city_stream(input_beats, num_cities, city_cache, city_stream);
    repair_depots(city_stream, num_cities, vehicle_capacity, coords, beat_stream);
    stream_beats_to_individual<BEAT_STREAM_INTERVAL>(beat_stream, output, 0, num_cities, start_end_data, num_cities);
    fitness = calculate_fitness(coords, depot_coord, num_cities);
}

inline void repair_fitness(
    hls::stream_of_blocks<IndividualAsBeats> &in,
    hls::stream_of_blocks<IndividualAsBeats> &out,
    int num_individuals,
    CityIndex num_cities,
    Capacity vehicle_capacity,
    const CityData city_cache[MAX_CACHE_ENTRIES]
) {
    CityIndex city_count = CityIndex(num_cities);
    BeatIndex total_city_beats = get_total_city_beats(num_cities);

    StartEndData start_end_data = get_start_end_data(0, num_cities - 1);
    Point depot_coord = get_coord(city_cache[num_cities]);

    REPAIR_FITNESS_INDIV_LOOP: for (int individual_idx = 0; individual_idx < num_individuals; ++individual_idx) {
        hls::read_lock<IndividualAsBeats> input(in);
        hls::write_lock<IndividualAsBeats> output(out);

        StartEndDataWithBeats data(start_end_data, input[start_end_data.start_beat], input[start_end_data.end_beat]);

        Fitness fitness;
        repair_and_calculate(
            input, output, city_count, total_city_beats, vehicle_capacity, city_cache, depot_coord, fitness, data);
        set_fitness(output, fitness, num_cities);
    }
}

#endif // REPAIR_FITNESS_HPP