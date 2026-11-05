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

#include "util.hpp"
#include "util_test.hpp"

#include <cmath>

static void init_all_0(IndividualAsBeats &ind) {
    for (int i = 0; i < HW_MAX_BEATS; ++i) {
        ind[i] = 0;
    }
}

static bool validate_expect(std::vector<int> &indices_not_to_check, int expected_value, IndividualAsBeats &dst_ind, int num_cities) {
    bool success = true;
    for (int i = 0; i < num_cities; ++i) {
        bool skip = false;
        for (size_t j = 0; j < indices_not_to_check.size(); ++j) {
            if (i == indices_not_to_check[j]) {
                skip = true;
                break;
            }
        }
        if (skip) continue;

        City val = get_city(dst_ind, i);
        if (val != expected_value) {
            std::cout << "Test FAILED at index " << i << ": Expected " << std::hex << expected_value << ", got " << val << std::endl;
            success = false;
        }
    }
    return success;
}

static bool validate(std::vector<int> &indices, std::vector<int> &expected_values, IndividualAsBeats &dst_ind) {
    bool success = true;
    for (size_t i = 0; i < indices.size(); ++i) {
        City val = get_city(dst_ind, indices[i]);
        if (val != expected_values[i]) {
            std::cout << "Test FAILED at index " << indices[i] << ": Expected " << std::hex << expected_values[i] << ", got " << val << std::endl;
            success = false;
        }
    }
    return success;
}

static int test1(){
    IndividualAsBeats dst_ind;
    hls::stream<BeatPacket> in_stream;

    init_all_0(dst_ind);

    int dst_start_idx = 2; 
    int n_cities_to_copy = 5;
    int dst_end_idx = dst_start_idx + n_cities_to_copy - 1;

    // Define test parameters with an unaligned start index
    int num_cities = std::ceil((dst_start_idx + n_cities_to_copy) / (double) HW_CITIES_PER_BEAT) * HW_CITIES_PER_BEAT;

    // Populate mock stream packets using city-setting utilities
    BeatPacket pkt1;
    pkt1.beat = 0;
    set_city(pkt1.beat, 0, 0x111);
    set_city(pkt1.beat, 1, 0x222);
    pkt1.n = 2;

    BeatPacket pkt2;
    pkt2.beat = 0;
    set_city(pkt2.beat, 0, 0x333);
    pkt2.n = 1;

    BeatPacket pkt3;
    pkt3.beat = 0;
    pkt3.n = 0;

    BeatPacket pkt4;
    pkt4.beat = 0;
    set_city(pkt4.beat, 0, 0x444);
    set_city(pkt4.beat, 1, 0x555);
    pkt4.n = 2;

    in_stream.write(pkt1);
    in_stream.write(pkt2);
    in_stream.write(pkt3);
    in_stream.write(pkt4);

    // Execute the HLS component
    stream_beats_to_individual<BEAT_STREAM_INTERVAL>(in_stream, dst_ind, dst_start_idx, n_cities_to_copy, StartEndDataWithBeats(get_start_end_data(dst_start_idx, dst_end_idx), 0, 0), num_cities);

    std::vector<int> indices = {dst_start_idx, dst_start_idx + 1, dst_start_idx + 2, dst_start_idx + 3, dst_start_idx + 4};
    std::vector<int> expected_values = {0x111, 0x222, 0x333, 0x444, 0x555};

    bool success = true;
    success &= validate(indices, expected_values, dst_ind);
    success &= validate_expect(indices, 0, dst_ind, num_cities);

    if (success) {
        std::cout << "Test 1 PASSED successfully!" << std::endl;
    }

    return success ? 0 : 1;
}

static int test2(){
    IndividualAsBeats dst_ind;
    hls::stream<BeatPacket> in_stream;

    init_all_0(dst_ind);

    // Define test parameters with an unaligned start index
    int dst_start_idx = HW_CITIES_PER_BEAT - 2; // Start at the second last city of the first beat
    int n_cities_to_copy = 5; // This will require reading from two packets
    int dst_end_idx = dst_start_idx + n_cities_to_copy - 1;
        
    int num_cities = std::ceil(n_cities_to_copy / HW_CITIES_PER_BEAT) * HW_CITIES_PER_BEAT * 2;

    // Populate mock stream packets using city-setting utilities
    BeatPacket pkt1;
    pkt1.beat = 0;
    set_city(pkt1.beat, 0, 0x111);
    set_city(pkt1.beat, 1, 0x222);
    pkt1.n = 2;

    BeatPacket pkt2;
    pkt2.beat = 0;
    set_city(pkt2.beat, 0, 0x333);
    pkt2.n = 1;

    BeatPacket pkt3;
    pkt3.beat = 0;
    pkt3.n = 0;

    BeatPacket pkt4;
    pkt4.beat = 0;
    set_city(pkt4.beat, 0, 0x444);
    set_city(pkt4.beat, 1, 0x555);
    pkt4.n = 2;

    in_stream.write(pkt1);
    in_stream.write(pkt2);
    in_stream.write(pkt3);
    in_stream.write(pkt4);

    // Execute the HLS component
    stream_beats_to_individual<BEAT_STREAM_INTERVAL>(in_stream, dst_ind, dst_start_idx, n_cities_to_copy, StartEndDataWithBeats(get_start_end_data(dst_start_idx, dst_end_idx), 0, 0), num_cities);

    std::vector<int> indices = {dst_start_idx, dst_start_idx + 1, dst_start_idx + 2, dst_start_idx + 3, dst_start_idx + 4};
    std::vector<int> expected_values = {0x111, 0x222, 0x333, 0x444, 0x555};

    bool success = true;
    success &= validate(indices, expected_values, dst_ind);
    success &= validate_expect(indices, 0, dst_ind, num_cities);

    if (success) {
        std::cout << "Test 2 PASSED successfully!" << std::endl;
    }

    return success ? 0 : 1;
}

static int test3(){
    IndividualAsBeats dst_ind;
    hls::stream<BeatPacket> in_stream;

    init_all_0(dst_ind);

    int n_cities_to_copy = 5; 
    int num_cities = std::ceil(n_cities_to_copy / (double) HW_CITIES_PER_BEAT) * HW_CITIES_PER_BEAT; // 8 cities total (2 beats)
    // Start at second-to-last city of the individual (index 6)
    int dst_start_idx = num_cities - 2; 
    int dst_end_idx = (dst_start_idx + n_cities_to_copy - 1) % num_cities;

    // Populate mock stream packets using city-setting utilities
    BeatPacket pkt1;
    pkt1.beat = 0;
    set_city(pkt1.beat, 0, 0x111);
    set_city(pkt1.beat, 1, 0x222);
    pkt1.n = 2;

    BeatPacket pkt2;
    pkt2.beat = 0;
    set_city(pkt2.beat, 0, 0x333);
    pkt2.n = 1;

    BeatPacket pkt3;
    pkt3.beat = 0;
    pkt3.n = 0;

    BeatPacket pkt4;
    pkt4.beat = 0;
    set_city(pkt4.beat, 0, 0x444);
    set_city(pkt4.beat, 1, 0x555);
    pkt4.n = 2;

    in_stream.write(pkt1);
    in_stream.write(pkt2);
    in_stream.write(pkt3);
    in_stream.write(pkt4);

    // Execute the HLS component
    stream_beats_to_individual<BEAT_STREAM_INTERVAL>(in_stream, dst_ind, dst_start_idx, n_cities_to_copy, StartEndDataWithBeats(get_start_end_data(dst_start_idx, dst_end_idx), 0, 0), num_cities);

    std::vector<int> indices = {dst_start_idx, dst_start_idx + 1, 0, 1, 2};
    std::vector<int> expected_values = {0x111, 0x222, 0x333, 0x444, 0x555};

    bool success = true;
    success &= validate(indices, expected_values, dst_ind);
    success &= validate_expect(indices, 0, dst_ind, num_cities);

    if (success) {
        std::cout << "Test 3 PASSED successfully!" << std::endl;
    }

    return success ? 0 : 1;
}

int test_integer_sqrt() {
    bool success = true;

    for (int i = 0; i < (1 << 8); ++i) {
        int expected = (int) std::floor(std::sqrt(i));
        int result = integer_sqrt<8>(i);
        if (result != expected) {
            std::cout << "Integer sqrt test FAILED for input " << i << ": Expected " << expected << ", got " << result << std::endl;
            success = false;
        }
    }

    if (success) {
        std::cout << "Integer sqrt test PASSED successfully!" << std::endl;
    } else {
        std::cout << "Integer sqrt test FAILED!" << std::endl;
    }

    return success ? 0 : 1;
}

static std::vector<std::pair<CityIndex, Beat>> drain_stream(hls::stream<BeatPacket> &stream) {
    std::vector<std::pair<CityIndex, Beat>> packets;
    while (!stream.empty()) {
        BeatPacket pkt = stream.read();
        packets.push_back({pkt.n, pkt.beat});
    }
    return packets;
}

static void print_packet_diff(
    const std::vector<std::pair<CityIndex, Beat>> &expected,
    const std::vector<std::pair<CityIndex, Beat>> &received
) {
    std::cout << "Expected " << expected.size() << " packet(s), received " << received.size() << " packet(s)" << std::endl;
    for (size_t i = 0; i < expected.size() || i < received.size(); ++i) {
        if (i < expected.size() && i < received.size()) {
            if (expected[i] != received[i]) {
                std::cout << "  Packet " << i << " mismatch: Expected (n=" << expected[i].first << ", beat=" << std::hex << expected[i].second 
                          << "), got (n=" << received[i].first << ", beat=" << received[i].second << ")" << std::endl;
            }
        } else if (i < expected.size()) {
            std::cout << "  Missing packet " << i << ": Expected (n=" << expected[i].first << ", beat=" << std::hex << expected[i].second << ")" << std::endl;
        } else {
            std::cout << "  Extra packet " << i << ": Got (n=" << received[i].first << ", beat=" << std::hex << received[i].second << ")" << std::endl;
        }
    }
}

static int test_beat_producer_partial() {
    hls::stream<BeatPacket> stream;
    BeatProducerState state;

    send_city(state, 0x111, stream);
    send_city(state, 0x222, stream);
    finalizeStream(state, stream);

    std::vector<std::pair<CityIndex, Beat>> expected;
    Beat b = 0;
    set_city(b, 0, 0x111);
    set_city(b, 1, 0x222);
    expected.push_back({2, b});

    std::vector<std::pair<CityIndex, Beat>> received = drain_stream(stream);

    bool pass = (received == expected);
    if (!pass) {
        std::cout << "test_beat_producer_partial FAILED!" << std::endl;
        print_packet_diff(expected, received);
        return 1;
    }
    std::cout << "test_beat_producer_partial PASSED successfully!" << std::endl;
    return 0;
}

static int test_beat_producer_full() {
    hls::stream<BeatPacket> stream;
    BeatProducerState state;

    for (int i = 0; i < HW_CITIES_PER_BEAT; ++i) {
        send_city(state, 0x1000 + i, stream);
    }
    finalizeStream(state, stream);

    std::vector<std::pair<CityIndex, Beat>> expected;
    Beat b = 0;
    for (int i = 0; i < HW_CITIES_PER_BEAT; ++i) {
        set_city(b, i, 0x1000 + i);
    }
    expected.push_back({HW_CITIES_PER_BEAT, b});

    std::vector<std::pair<CityIndex, Beat>> received = drain_stream(stream);

    bool pass = (received == expected);
    if (!pass) {
        std::cout << "test_beat_producer_full FAILED!" << std::endl;
        print_packet_diff(expected, received);
        return 1;
    }
    std::cout << "test_beat_producer_full PASSED successfully!" << std::endl;
    return 0;
}

static int test_beat_producer_multibeat() {
    hls::stream<BeatPacket> stream;
    BeatProducerState state;

    for (int i = 0; i < 19; ++i) {
        send_city(state, 0x2000 + i, stream);
    }
    finalizeStream(state, stream);

    std::vector<std::pair<CityIndex, Beat>> expected;
    const int total_cities = 19;
    for (int start = 0; start < total_cities; start += HW_CITIES_PER_BEAT) {
        int n = std::min(static_cast<int>(HW_CITIES_PER_BEAT), total_cities - start);
        Beat b = 0;
        for (int i = 0; i < n; ++i) {
            set_city(b, i, 0x2000 + start + i);
        }
        expected.push_back({static_cast<CityIndex>(n), b});
    }

    std::vector<std::pair<CityIndex, Beat>> received = drain_stream(stream);

    bool pass = (received == expected);
    if (!pass) {
        std::cout << "test_beat_producer_multibeat FAILED!" << std::endl;
        print_packet_diff(expected, received);
        return 1;
    }
    std::cout << "test_beat_producer_multibeat PASSED successfully!" << std::endl;
    return 0;
}

int test_beat_producer() {
    int errors = 0;
    errors += test_beat_producer_partial();
    errors += test_beat_producer_full();
    errors += test_beat_producer_multibeat();
    return errors;
}

static int test_two_beats_warp_around() {
    IndividualAsBeats dst_ind;
    hls::stream<BeatPacket> in_stream;

    init_all_0(dst_ind);

    int num_cities = 2 * HW_CITIES_PER_BEAT;

    int dst_start_idx = 2 * HW_CITIES_PER_BEAT - 1;
    int dst_end_idx = 2 * HW_CITIES_PER_BEAT - 2;
    int n_cities_to_copy = num_cities;

    // Send 2 packets of HW_CITIES_PER_BEAT cities each
    // Packet 1: first HW_CITIES_PER_BEAT cities
    BeatPacket pkt1;
    pkt1.beat = 0;
    for (int i = 0; i < HW_CITIES_PER_BEAT; i++) {
        set_city(pkt1.beat, i, 0x100 + i + 1);
    }
    pkt1.n = HW_CITIES_PER_BEAT;
    in_stream.write(pkt1);

    // Packet 2: next HW_CITIES_PER_BEAT cities
    BeatPacket pkt2;
    pkt2.beat = 0;
    for (int i = 0; i < HW_CITIES_PER_BEAT; i++) {
        set_city(pkt2.beat, i, 0x100 + HW_CITIES_PER_BEAT + i + 1);
    }
    pkt2.n = HW_CITIES_PER_BEAT;
    in_stream.write(pkt2);

    StartEndData start_end_data = get_start_end_data(dst_start_idx, dst_end_idx);
    StartEndDataWithBeats data_with_beats(start_end_data, 0, 0);

    stream_beats_to_individual<BEAT_STREAM_INTERVAL>(
        in_stream, dst_ind, dst_start_idx, n_cities_to_copy,
        data_with_beats, num_cities
    );

    std::vector<int> indices;
    std::vector<int> expected_values;

    for (int k = 0; k < num_cities; k++) {
        int idx = wrap_city_index(dst_start_idx + k, num_cities);
        indices.push_back(idx);
        expected_values.push_back(0x100 + k + 1);
    }

    bool success = true;
    success &= validate(indices, expected_values, dst_ind);
    success &= validate_expect(indices, 0, dst_ind, num_cities);

    if (success) {
        std::cout << "test_two_beats_warp_around PASSED successfully!" << std::endl;
    } else {
        std::cout << "test_two_beats_warp_around FAILED!" << std::endl;
    }

    return success ? 0 : 1;
}

static int test_odd_cities_warp_around() {
    IndividualAsBeats dst_ind;
    hls::stream<BeatPacket> in_stream;

    init_all_0(dst_ind);

    int num_cities = 2 * HW_CITIES_PER_BEAT + 1;

    // Start at the last city of the tour (unaligned / partial beat)
    int dst_start_idx = num_cities - 1;
    int n_cities_to_copy = HW_CITIES_PER_BEAT + 1;
    int dst_end_idx = wrap_city_index(dst_start_idx + n_cities_to_copy - 1, num_cities);

    // Send packet 1: HW_CITIES_PER_BEAT cities
    // The first city fills the last beat (index num_cities - 1),
    // and the remaining HW_CITIES_PER_BEAT - 1 cities spill over into beat 0!
    BeatPacket pkt1;
    pkt1.beat = 0;
    for (int i = 0; i < HW_CITIES_PER_BEAT; i++) {
        set_city(pkt1.beat, i, 0x200 + i + 1);
    }
    pkt1.n = HW_CITIES_PER_BEAT;
    in_stream.write(pkt1);

    // Send packet 2: 1 city to complete beat 0
    BeatPacket pkt2;
    pkt2.beat = 0;
    set_city(pkt2.beat, 0, 0x200 + HW_CITIES_PER_BEAT + 1);
    pkt2.n = 1;
    in_stream.write(pkt2);

    StartEndData start_end_data = get_start_end_data(dst_start_idx, dst_end_idx);
    StartEndDataWithBeats data_with_beats(start_end_data, 0, 0);

    stream_beats_to_individual<BEAT_STREAM_INTERVAL>(
        in_stream, dst_ind, dst_start_idx, n_cities_to_copy,
        data_with_beats, num_cities
    );

    std::vector<int> indices;
    std::vector<int> expected_values;

    for (int k = 0; k < n_cities_to_copy; k++) {
        int idx = wrap_city_index(dst_start_idx + k, num_cities);
        indices.push_back(idx);
        expected_values.push_back(0x200 + k + 1);
    }

    bool success = true;
    success &= validate(indices, expected_values, dst_ind);
    success &= validate_expect(indices, 0, dst_ind, num_cities);

    if (success) {
        std::cout << "test_odd_cities_warp_around PASSED successfully!" << std::endl;
    } else {
        std::cout << "test_odd_cities_warp_around FAILED!" << std::endl;
    }

    return success ? 0 : 1;
}

static int test_odd_cities_spillover_warp_around() {
    IndividualAsBeats dst_ind;
    hls::stream<BeatPacket> in_stream;

    init_all_0(dst_ind);

    int num_cities = 2 * HW_CITIES_PER_BEAT + 1;

    // Start one city before the last beat (e.g. index 3 for num_cities = 5, where last city is 4)
    int dst_start_idx = num_cities - 2;
    int n_cities_to_copy = HW_CITIES_PER_BEAT + 2;
    int dst_end_idx = wrap_city_index(dst_start_idx + n_cities_to_copy - 1, num_cities);

    // Send packet 1: HW_CITIES_PER_BEAT cities
    // City 1 fills beat 1, city 2 spills over into the last beat (index num_cities - 1),
    // reaching the end of the tour!
    BeatPacket pkt1;
    pkt1.beat = 0;
    for (int i = 0; i < HW_CITIES_PER_BEAT; i++) {
        set_city(pkt1.beat, i, 0x300 + i + 1);
    }
    pkt1.n = HW_CITIES_PER_BEAT;
    in_stream.write(pkt1);

    // Send packet 2: HW_CITIES_PER_BEAT cities starting from beat 0
    BeatPacket pkt2;
    pkt2.beat = 0;
    for (int i = 0; i < HW_CITIES_PER_BEAT; i++) {
        set_city(pkt2.beat, i, 0x300 + HW_CITIES_PER_BEAT + i + 1);
    }
    pkt2.n = HW_CITIES_PER_BEAT;
    in_stream.write(pkt2);

    StartEndData start_end_data = get_start_end_data(dst_start_idx, dst_end_idx);
    StartEndDataWithBeats data_with_beats(start_end_data, 0, 0);

    stream_beats_to_individual<BEAT_STREAM_INTERVAL>(
        in_stream, dst_ind, dst_start_idx, n_cities_to_copy,
        data_with_beats, num_cities
    );

    std::vector<int> indices;
    std::vector<int> expected_values;

    for (int k = 0; k < n_cities_to_copy; k++) {
        int idx = wrap_city_index(dst_start_idx + k, num_cities);
        indices.push_back(idx);
        expected_values.push_back(0x300 + k + 1);
    }

    bool success = true;
    success &= validate(indices, expected_values, dst_ind);
    success &= validate_expect(indices, 0, dst_ind, num_cities);

    if (success) {
        std::cout << "test_odd_cities_spillover_warp_around PASSED successfully!" << std::endl;
    } else {
        std::cout << "test_odd_cities_spillover_warp_around FAILED!" << std::endl;
    }

    return success ? 0 : 1;
}

int test_util() {
    int errors = test1();
    errors += test2();
    errors += test3();
    errors += test_integer_sqrt();
    errors += test_beat_producer();
    errors += test_two_beats_warp_around();
    errors += test_odd_cities_warp_around();
    errors += test_odd_cities_spillover_warp_around();
    return errors;
}
