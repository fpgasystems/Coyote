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

#ifndef TYPES_HPP
#define TYPES_HPP

#include <ap_int.h>
#include <ap_axi_sdata.h>
#include <hls_stream.h>

#include "ga_encoding_constants.hpp"

// ============================================================================
// Type Definitions & Structs
// ============================================================================

// ----------------------------------------------------------------------------
// 1. Bitfield Index & Counter Types
// ----------------------------------------------------------------------------
typedef ap_uint<MAX_CITIES_LOG2 + 1>                  CityIndex;
typedef ap_uint<HW_MAX_BEATS_LOG2 + 1>                BeatIndex;
typedef ap_uint<HW_CITIES_PER_BEAT_LOG2 + 1>          CityBeatIndex;
typedef ap_uint<NODE_CACHE_ENTRIES_PER_BEAT_LOG2 + 1> BeatCacheIndex;
typedef ap_uint<HW_BEATS_PER_AXI_BEAT_LOG2 + 1>       BeatAxiIndex;

// ----------------------------------------------------------------------------
// 2. Problem & Node Data Types
// ----------------------------------------------------------------------------
typedef ap_uint<COORD_BITS>    Coord;
typedef ap_uint<CAPACITY_BITS> Capacity;
typedef ap_uint<NODE_ID_BITS>  NodeId;

struct Point {
    Coord x;
    Coord y;

    bool operator==(const Point &other) const {
        return x == other.x && y == other.y;
    }
    bool operator!=(const Point &other) const {
        return !(*this == other);
    }
};

struct CityData {
    Point coord;
    Capacity demand;

    bool operator==(const CityData &other) const {
        return coord == other.coord && demand == other.demand;
    }
    bool operator!=(const CityData &other) const {
        return !(*this == other);
    }
};

struct CoordElement {
    Point coord;
    bool is_depot;
    bool last;

    bool operator==(const CoordElement &other) const {
        return coord == other.coord && is_depot == other.is_depot && last == other.last;
    }
    bool operator!=(const CoordElement &other) const {
        return !(*this == other);
    }
};

// ----------------------------------------------------------------------------
// 3. Individual Genome & City / Fitness Types
// ----------------------------------------------------------------------------
typedef ap_uint<CITY_BITS>     City;
typedef ap_uint<FITNESS_BITS>  Fitness;
typedef ap_uint<8>             Probability;

struct CityPair {
    CityIndex start;
    CityIndex end;
    Probability prob_rnd;

    CityPair() : start(0), end(0), prob_rnd(0) {}
    CityPair(CityIndex s, CityIndex e, Probability p = 0) : start(s), end(e), prob_rnd(p) {}

    bool operator==(const CityPair &other) const {
        return start == other.start && end == other.end && prob_rnd == other.prob_rnd;
    }
};

struct CityElement {
    City city;
    Capacity demand;
    Point coord;

    bool operator==(const CityElement &other) const {
        return city == other.city && demand == other.demand && coord == other.coord;
    }
    bool operator!=(const CityElement &other) const {
        return !(*this == other);
    }
};

// ----------------------------------------------------------------------------
// 4. Beat, Stream & Cache Types
// ----------------------------------------------------------------------------
typedef ap_uint<HW_BEAT_WIDTH>          Beat;
typedef ap_uint<AXI_BEAT_WIDTH>         AxiBeat;
typedef ap_axiu<AXI_BEAT_WIDTH, 0, 0, 0> axi_word_t;
typedef Beat                            IndividualAsBeats[HW_MAX_BEATS];
typedef AxiBeat                         CityCacheBeat;
typedef ap_uint<NODE_CACHE_ENTRY_BITS>  CityCacheEntry;


struct StartEndData {
    const BeatIndex start_beat;
    const CityIndex start_city;
    const BeatIndex end_beat;
    const CityIndex end_city;

    StartEndData(BeatIndex s_beat, CityIndex s_city, BeatIndex e_beat, CityIndex e_city)
        : start_beat(s_beat), start_city(s_city), end_beat(e_beat), end_city(e_city) {}
};

// ============================================================================
// Methods & Inline Helper Functions
// ============================================================================

// ----------------------------------------------------------------------------
// 1. Indexing & Beat Navigation Methods
// ----------------------------------------------------------------------------
static inline CityIndex wrap_city_index(CityIndex idx, CityIndex num_cities) {
    #pragma HLS INLINE
    return (idx >= num_cities) ? CityIndex(idx - num_cities) : idx;
}

static inline CityIndex wrap_city_index(int idx, int num_cities) {
    #pragma HLS INLINE
    return (idx >= num_cities) ? CityIndex(idx - num_cities) : CityIndex(idx);
}

static inline BeatIndex get_total_city_beats(CityIndex num_cities) {
    #pragma HLS INLINE
    return (num_cities + HW_CITIES_PER_BEAT - 1) >> HW_CITIES_PER_BEAT_LOG2;
}

static inline BeatIndex get_total_city_beats(int num_cities) {
    #pragma HLS INLINE
    return (num_cities + HW_CITIES_PER_BEAT - 1) >> HW_CITIES_PER_BEAT_LOG2;
}

static inline BeatIndex get_total_beats(CityIndex num_cities) {
    #pragma HLS INLINE
    return get_total_city_beats(num_cities) + HW_FITNESS_BEATS;
}

static inline BeatIndex get_total_beats(int num_cities) {
    #pragma HLS INLINE
    return get_total_city_beats(num_cities) + HW_FITNESS_BEATS;
}

static inline BeatIndex get_beat_idx(CityIndex global_idx) {
    #pragma HLS INLINE
    return global_idx >> HW_CITIES_PER_BEAT_LOG2;
}

static inline BeatIndex get_beat_idx(int global_idx) {
    #pragma HLS INLINE
    return global_idx >> HW_CITIES_PER_BEAT_LOG2;
}

template <typename T>
static inline CityBeatIndex get_city_beat_idx(T val) {
    #pragma HLS INLINE
    return val & (HW_CITIES_PER_BEAT - 1);
}


static inline void get_beat_city(CityIndex global_idx, BeatIndex &beat_idx, CityIndex &city_idx) {
    #pragma HLS INLINE
    beat_idx = get_beat_idx(global_idx);
    city_idx = get_city_beat_idx(global_idx);
}

static inline void get_beat_city(int global_idx, BeatIndex &beat_idx, CityIndex &city_idx) {
    #pragma HLS INLINE
    beat_idx = get_beat_idx(global_idx);
    city_idx = get_city_beat_idx(global_idx);
}

static inline StartEndData get_start_end_data(CityIndex start_idx, CityIndex end_idx) {
    #pragma HLS INLINE
    BeatIndex start_beat;
    CityIndex start_city;
    BeatIndex end_beat;
    CityIndex end_city;
    get_beat_city(start_idx, start_beat, start_city);
    get_beat_city(end_idx, end_beat, end_city);
    return StartEndData(start_beat, start_city, end_beat, end_city);
}

static inline CityIndex get_first_city_index() {
    #pragma HLS INLINE
    return 0;
}

static inline CityIndex get_last_city_index(CityIndex num_cities, BeatIndex beat_idx) {
    #pragma HLS INLINE
    BeatIndex last_city_beat = (num_cities - 1) >> HW_CITIES_PER_BEAT_LOG2;
    return (beat_idx == last_city_beat) ? CityIndex(get_city_beat_idx(num_cities - 1)) : CityIndex(HW_CITIES_PER_BEAT - 1);
}

// ----------------------------------------------------------------------------
// 2. City-Level Accessors (Node ID & Depot Flag inside a City)
// ----------------------------------------------------------------------------
static inline NodeId get_node_id(City val) {
    #pragma HLS INLINE
    return val.range(NODE_ID_BITS - 1, 0);
}

static inline void set_node_id(City &val, NodeId id) {
    #pragma HLS INLINE
    val.range(NODE_ID_BITS - 1, 0) = id;
}

static inline bool get_is_depot(City val) {
    #pragma HLS INLINE
    return val[DEPOT_FLAG_OFFSET];
}

static inline void set_is_depot(City &val, bool depot) {
    #pragma HLS INLINE
    val[DEPOT_FLAG_OFFSET] = depot;
}

// ----------------------------------------------------------------------------
// 3. Beat-Level & Individual City Accessors
// ----------------------------------------------------------------------------
static inline City get_city(const Beat &beat, CityIndex city_idx) {
    #pragma HLS INLINE
    CityIndex low = city_idx << CITY_BITS_LOG2;
    CityIndex high = low + CITY_BITS - 1;
    return beat.range(high, low);
}

static inline void set_city(Beat &beat, CityIndex city_idx, City val) {
    #pragma HLS INLINE
    CityIndex low = city_idx << CITY_BITS_LOG2;
    CityIndex high = low + CITY_BITS - 1;
    beat.range(high, low) = val;
}

static inline City get_city(const IndividualAsBeats &ind, CityIndex global_idx) {
    #pragma HLS INLINE
    BeatIndex beat_idx;
    CityIndex city_idx;
    get_beat_city(global_idx, beat_idx, city_idx);
    return get_city(ind[beat_idx], city_idx);
}

static inline void set_city(IndividualAsBeats &ind, CityIndex global_idx, City val) {
    #pragma HLS INLINE
    BeatIndex beat_idx;
    CityIndex city_idx;
    get_beat_city(global_idx, beat_idx, city_idx);
    set_city(ind[beat_idx], city_idx, val);
}

static inline City consume_next_city(Beat &beat) {
    #pragma HLS INLINE
    City city = beat.range(CITY_BITS - 1, 0);
    beat >>= CITY_BITS;
    return city;
}

// ----------------------------------------------------------------------------
// 4. Trailing Dedicated Beat Fitness Accessors
// ----------------------------------------------------------------------------
static inline Fitness get_fitness(const IndividualAsBeats &ind, CityIndex num_cities) {
    #pragma HLS INLINE
    BeatIndex fitness_beat_idx = get_total_city_beats(num_cities);
    return ind[fitness_beat_idx].range(FITNESS_BITS - 1, 0);
}

static inline void set_fitness(IndividualAsBeats &ind, Fitness val, CityIndex num_cities) {
    #pragma HLS INLINE
    BeatIndex fitness_beat_idx = get_total_city_beats(num_cities);
    Beat beat = 0;
    beat.range(FITNESS_BITS - 1, 0) = val;
    ind[fitness_beat_idx] = beat;
}

// ----------------------------------------------------------------------------
// 5. Node Cache & Stream Consumer Helpers
// ----------------------------------------------------------------------------
static inline Point get_coord(const CityCacheEntry &entry) {
    #pragma HLS INLINE
    Coord x = entry.range(NODE_CACHE_COORD_X_OFFSET + COORD_BITS - 1, NODE_CACHE_COORD_X_OFFSET);
    Coord y = entry.range(NODE_CACHE_COORD_Y_OFFSET + COORD_BITS - 1, NODE_CACHE_COORD_Y_OFFSET);
    return Point{x, y};
}

static inline Point get_coord(const CityData &cd) {
    #pragma HLS INLINE
    return cd.coord;
}

static inline Capacity get_demand(const CityCacheEntry &entry) {
    #pragma HLS INLINE
    return entry.range(NODE_CACHE_DEMAND_OFFSET + CAPACITY_BITS - 1, NODE_CACHE_DEMAND_OFFSET);
}

static inline CityCacheEntry consume_next_cache_entry(CityCacheBeat &beat) {
    #pragma HLS INLINE
    CityCacheEntry entry = beat.range(NODE_CACHE_ENTRY_BITS - 1, 0);
    beat >>= NODE_CACHE_ENTRY_BITS;
    return entry;
}

static inline CityData consume_next_city_data(CityCacheBeat &beat) {
    #pragma HLS INLINE
    CityCacheEntry entry = consume_next_cache_entry(beat);
    Point coord = get_coord(entry);
    Capacity demand = get_demand(entry);
    return CityData{coord, demand};
}


static inline Beat consume_next_hw_beat(AxiBeat &beat) {
    #pragma HLS INLINE
    Beat hw_beat = beat.range(HW_BEAT_WIDTH - 1, 0);
    beat >>= HW_BEAT_WIDTH;
    return hw_beat;
}

#endif // TYPES_HPP
