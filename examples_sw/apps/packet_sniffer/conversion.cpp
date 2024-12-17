#include <string>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <sys/time.h>

#include "include/conversion.hpp"

#pragma GCC diagnostic ignored "-Wunused-result"

struct filter_config {
    bool ignore_udp_ipv4_payload;
    bool ignore_udp_ipv6_payload;
    bool ignore_tcp_ipv4_payload;
    bool ignore_rocev2_ipv4_payload;
} filter_cfg;

// Definitions copied from pcap.h
struct pcap_file_header {
	u_int magic;
	u_short version_major;
	u_short version_minor;
	int thiszone;	/* gmt to local correction; this is always 0 */
	u_int sigfigs;	/* accuracy of timestamps; this is always 0 */
	u_int snaplen;	/* max length saved portion of each pkt */
	u_int linktype;	/* data link type (LINKTYPE_*) */
};
struct pcap_pkthdr {
	struct timeval ts;	/* time stamp */
	u_int caplen;	/* length of portion present */
	u_int len;	/* length of this packet (off wire) */
};

void pcap_conversion(std::string raw, std::string pcap) {
    FILE *raw_f = fopen(raw.c_str(), "r");
    FILE *pcap_f = fopen(pcap.c_str(), "wb");

    // Parsing Filter Congifuration
    uint64_t raw_filter_config = 0;
    fscanf(raw_f, "%lx", &raw_filter_config);
    filter_cfg.ignore_udp_ipv4_payload = (raw_filter_config & (1ULL << 23)) ? true : false;
    filter_cfg.ignore_udp_ipv6_payload = (raw_filter_config & (1ULL << 25)) ? true : false;
    filter_cfg.ignore_tcp_ipv4_payload = (raw_filter_config & (1ULL << 27)) ? true : false;
    filter_cfg.ignore_rocev2_ipv4_payload = (raw_filter_config & (1ULL << 31)) ? true : false;

    // Write PCAP Header
    struct pcap_file_header pcap_hdr = {0xa1b2c3d4, 2, 4, 0, 0, 65535, 1};
    fwrite(&pcap_hdr, 1, 24, pcap_f);

    // Read Output
    char tmp[100];
    unsigned char *buf = (unsigned char *)malloc(100 * 1024 * 1024); // 100M
    int buf_len = 0;
    while (fscanf(raw_f, "%s", tmp) != EOF) {
        for (int i = 0; i < 8; ++i) {
            fscanf(raw_f, "%hhx", (buf + (buf_len++)));
        }
    }

    int n_packet = 0;
    int n_bytes_read = 0;
    struct pcap_pkthdr pkt_hdr;
    while (n_bytes_read < buf_len) {
        pkt_hdr.ts.tv_sec = n_packet;
        pkt_hdr.ts.tv_usec = 0;
        pkt_hdr.caplen = 14; // eth frame header len
        pkt_hdr.len = 14;
        if (buf[n_bytes_read + 12] == 0x86 && buf[n_bytes_read + 13] == 0xdd) { // IPv6
            if (filter_cfg.ignore_udp_ipv6_payload && buf[n_bytes_read + 20] == 0x11) { // ignore UDP payload
                pkt_hdr.caplen += 40; // IPv6 header len
                pkt_hdr.caplen += 8; // UDP header len
            } else {
                pkt_hdr.caplen += 40; // IPv6 header len
                pkt_hdr.caplen += buf[n_bytes_read + 18] * 256 + buf[n_bytes_read + 19]; // IPv6 payload len
                if (pkt_hdr.caplen < 64) pkt_hdr.caplen = 64; // possible padding
            }
            pkt_hdr.len += 40;
            pkt_hdr.len += buf[n_bytes_read + 18] * 256 + buf[n_bytes_read + 19];
            if (pkt_hdr.len < 64) pkt_hdr.len = 64;
        } else if (buf[n_bytes_read + 12] == 0x08 && buf[n_bytes_read + 13] == 0x00) { // IPv4
            if (filter_cfg.ignore_udp_ipv4_payload && buf[n_bytes_read + 23] == 0x11) { // ignore UDP payload
                pkt_hdr.caplen += 20; // IPv4 header (min) len
                pkt_hdr.caplen += 8; // UDP header len
            } else if (filter_cfg.ignore_tcp_ipv4_payload && buf[n_bytes_read + 23] == 0x06) { // ignore TCP payload
                pkt_hdr.caplen += 20; // IPv4 header (min) len
                pkt_hdr.caplen += 20; // TCP header (min) len
            } else if (filter_cfg.ignore_rocev2_ipv4_payload && buf[n_bytes_read + 23] == 0x11 && buf[n_bytes_read + 36] == 0xb7 && buf[n_bytes_read + 37] == 0x12) { // ignore RoCEv2 payload
                pkt_hdr.caplen += 20; // IPv4 header (min) len
                pkt_hdr.caplen += 8; // UDP header len
                pkt_hdr.caplen += 12; // RoCEv2 header len
                // determine roce optional header len
                if (buf[n_bytes_read + 42] == 0x10 || buf[n_bytes_read + 42] == 0x0d || buf[n_bytes_read + 42] == 0x0f || buf[n_bytes_read + 42] == 0x11) {
                    // AETH
                    pkt_hdr.caplen += 4;
                } else if (buf[n_bytes_read + 42] == 0x0a || buf[n_bytes_read + 42] == 0x06 || buf[n_bytes_read + 42] == 0x0b || buf[n_bytes_read + 42] == 0x0c) {
                    // RETH
                    pkt_hdr.caplen += 16;
                }
            } else {
                pkt_hdr.caplen += buf[n_bytes_read + 16] * 256 + buf[n_bytes_read + 17]; // IPv4 total len
                if (pkt_hdr.caplen < 64) pkt_hdr.caplen = 64; // possible padding
            }
            pkt_hdr.len += buf[n_bytes_read + 16] * 256 + buf[n_bytes_read + 17];
            if (pkt_hdr.len < 64) pkt_hdr.len = 64;
        } else { // Other (Length)
            pkt_hdr.caplen += buf[n_bytes_read + 12] * 256 + buf[n_bytes_read + 13];
            pkt_hdr.len += buf[n_bytes_read + 12] * 256 + buf[n_bytes_read + 13];
        }
        // fprintf(stdout, "packet len %d\n", pkt_hdr.caplen);
        fwrite(&pkt_hdr.ts, 1, 8, pcap_f);
        fwrite(&pkt_hdr.caplen, 1, 4, pcap_f);
        fwrite(&pkt_hdr.len, 1, 4, pcap_f);
        fwrite(buf + n_bytes_read, 1, pkt_hdr.caplen, pcap_f);
        ++n_packet;
        n_bytes_read += ((pkt_hdr.caplen - 1) / 64 * 64 + 64);
    }

    fclose(raw_f);
    fclose(pcap_f);
}

#pragma GCC diagnostic warning "-Wunused-result"