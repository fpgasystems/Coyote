#ifndef ZERO_IN_RAW_DOWNSAMPLE_HPP_
#define ZERO_IN_RAW_DOWNSAMPLE_HPP_

#include "ap_int.h"
#include "hls_stream.h"
#include "ap_axi_sdata.h"
#include "defines.h"

namespace zero_in_raw {

static const unsigned int ZERO_IN_PIXELS = 65536;
static const unsigned int COYOTE_AXI_BYTES = COYOTE_AXI_STREAM_BITS / 8;
static const unsigned long long ONE_SAMPLE_PER_BEAT_MIN_LEN =
    ((unsigned long long) ZERO_IN_PIXELS - 1) * COYOTE_AXI_BYTES + 1;

static ap_uint<8> get_byte(const axi_s &packet, unsigned int byte_idx) {
    #pragma HLS INLINE
    return packet.data.range((byte_idx + 1) * 8 - 1, byte_idx * 8);
}

static unsigned long long read_len_le(const axi_s &packet) {
    #pragma HLS INLINE
    unsigned long long raw_len = 0;
    for (unsigned int b = 0; b < 8; b++) {
        #pragma HLS UNROLL
        raw_len |= ((unsigned long long) get_byte(packet, b)) << (8 * b);
    }
    return raw_len;
}

static void write_normalized_token(ap_uint<8> raw_byte, hls::stream<input_t> &data_out) {
    #pragma HLS INLINE
    ap_uint<8> inverted = 255 - raw_byte;
    input_t token;
    token[0] = input_t::value_type((float) inverted / 255.0f);
    data_out.write(token);
}

static void write_padding_tokens(unsigned int already_written, hls::stream<input_t> &data_out) {
    for (unsigned int i = already_written; i < ZERO_IN_PIXELS; i++) {
        #pragma HLS PIPELINE II=1
        write_normalized_token(0, data_out);
    }
}

static void raw_bitstream_downsample_to_input_stream(
    hls::stream<axi_s> &axi_in,
    hls::stream<input_t> &data_out
) {
    #pragma HLS INLINE OFF

    axi_s header = axi_in.read();
    unsigned long long raw_len = read_len_le(header);

    if (raw_len == 0) {
        write_padding_tokens(0, data_out);
        return;
    }

    if (raw_len <= ZERO_IN_PIXELS) {
        unsigned int written = 0;
        axi_s packet;
        for (unsigned long long raw_idx = 0; raw_idx < raw_len; raw_idx++) {
            #pragma HLS PIPELINE II=1
            unsigned int lane = raw_idx % COYOTE_AXI_BYTES;
            if (lane == 0) {
                packet = axi_in.read();
            }
            write_normalized_token(get_byte(packet, lane), data_out);
            written++;
        }
        write_padding_tokens(written, data_out);
        return;
    }

    const unsigned long long numerator = raw_len - 1;
    const unsigned long long denom = ZERO_IN_PIXELS - 1;
    const unsigned long long stride = numerator / denom;
    const unsigned long long remainder_step = numerator % denom;

    if (raw_len < ONE_SAMPLE_PER_BEAT_MIN_LEN) {
        unsigned long long target_idx = 0;
        unsigned long long remainder_acc = 0;
        unsigned int sample_idx = 0;
        axi_s packet;

        for (unsigned long long raw_idx = 0; raw_idx < raw_len; raw_idx++) {
            #pragma HLS PIPELINE II=1
            unsigned int lane = raw_idx % COYOTE_AXI_BYTES;
            if (lane == 0) {
                packet = axi_in.read();
            }
            if (raw_idx == target_idx) {
                write_normalized_token(get_byte(packet, lane), data_out);
                sample_idx++;
                target_idx += stride;
                remainder_acc += remainder_step;
                if (remainder_acc >= denom) {
                    target_idx++;
                    remainder_acc -= denom;
                }
            }
        }
        return;
    }

    unsigned long long target_idx = 0;
    unsigned long long remainder_acc = 0;
    unsigned int sample_idx = 0;
    const unsigned long long num_beats = (raw_len + COYOTE_AXI_BYTES - 1) / COYOTE_AXI_BYTES;

    for (unsigned long long beat = 0; beat < num_beats; beat++) {
        #pragma HLS PIPELINE II=1
        axi_s packet = axi_in.read();
        unsigned long long beat_base = beat * COYOTE_AXI_BYTES;
        if (target_idx >= beat_base && target_idx < beat_base + COYOTE_AXI_BYTES) {
            unsigned int lane = target_idx - beat_base;
            write_normalized_token(get_byte(packet, lane), data_out);
            sample_idx++;
            target_idx += stride;
            remainder_acc += remainder_step;
            if (remainder_acc >= denom) {
                target_idx++;
                remainder_acc -= denom;
            }
        }
    }
}

}

#endif
