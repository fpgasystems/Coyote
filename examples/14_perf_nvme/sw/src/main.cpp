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

// Includes
#include <chrono>
#include <cstdint>
#include <cstring>
#include <iomanip>
#include <iostream>
#include <string>
#include <vector>
#include <boost/program_options.hpp>

#include <coyote/cThread.hpp>

// Constants
#define CLOCK_PERIOD_NS 4
#define DEFAULT_VFPGA_ID 0
#define DEFAULT_NSID 1

// Coyote LOCAL_OFFLOAD / LOCAL_SYNC chunk limit
static constexpr uint64_t OFFLOAD_MAX = 128ULL * 1024ULL * 1024ULL;

// CSR register map; must match perf_nvme_axi_ctrl_parser
enum class BenchmarkRegisters : uint32_t {
    CTRL_REG            = 0,    // W1S: bit0 = start READ, bit1 = start WRITE
    SENT_REG            = 1,    // RO: total commands issued across all active devices
    DONE_REG            = 2,    // RO: total completions received across all active devices
    TIMER_REG           = 3,    // RO: clock cycles (max across active devices)
    VADDR_REG           = 4,    // WR: card memory base address
    CHUNK_SIZE_REG      = 5,    // WR: bytes per NVMe command
    N_REPS_REG          = 6,    // WR: number of NVMe commands per device
    LBA_REG             = 7,    // WR: starting LBA byte offset
    DEV_MASK_REG        = 8,    // WR: per-device participation mask
    NSID_REG            = 9,    // WR: NVMe namespace ID
    MAX_OUTSTANDING_REG = 10,   // WR: max in-flight commands per device
    ERROR_REG           = 11    // RO: last error code on cq_rsp (sticky until next CTRL pulse)
};

// 01 written to CTRL_REG starts a read operation and 10 written to CTRL starts a write
enum class BenchmarkOperation : uint8_t {
    START_RD = 0x1,
    START_WR = 0x2
};

// Parse a size string like "64M", "128K" or "1G"
static uint64_t parseSize(const std::string& s) {
    if (s.empty()) {
        throw std::runtime_error("empty size string");
    }
    char* end = nullptr;
    uint64_t val = std::strtoull(s.c_str(), &end, 0);
    switch (end ? *end : '\0') {
        case 'K': case 'k': val *= 1024ULL; break;
        case 'M': case 'm': val *= 1024ULL * 1024; break;
        case 'G': case 'g': val *= 1024ULL * 1024 * 1024; break;
        case '\0':                                       break;
        default:
            throw std::runtime_error("unknown size suffix in '" + s + "'");
    }
    return val;
}

static std::string formatSize(uint64_t bytes) {
    if (bytes >= 1024ULL * 1024 * 1024) return std::to_string(bytes / (1024ULL * 1024 * 1024)) + " GB";
    if (bytes >= 1024ULL * 1024)        return std::to_string(bytes / (1024ULL * 1024)) + " MB";
    if (bytes >= 1024ULL)               return std::to_string(bytes / 1024ULL) + " KB";
    return std::to_string(bytes) + " B";
}

static std::string formatBW(double bytes_per_sec) {
    char buf[32];
    if (bytes_per_sec >= 1024.0 * 1024.0 * 1024.0)
        snprintf(buf, sizeof(buf), "%.2f GB/s", bytes_per_sec / (1024.0 * 1024.0 * 1024.0));
    else if (bytes_per_sec >= 1024.0 * 1024.0)
        snprintf(buf, sizeof(buf), "%.2f MB/s", bytes_per_sec / (1024.0 * 1024.0));
    else if (bytes_per_sec >= 1024.0)
        snprintf(buf, sizeof(buf), "%.2f KB/s", bytes_per_sec / 1024.0);
    else
        snprintf(buf, sizeof(buf), "%.2f B/s",  bytes_per_sec);
    return std::string(buf);
}

// Run one benchmark pass and report the aggregated bandwidth
static void run_bench(
    coyote::cThread& coyote_thread, void* buf, uint64_t total_size_per_dev,
    uint64_t chunk_size, uint32_t n_reps, uint16_t dev_mask, uint32_t n_active_devs,
    uint32_t max_outstanding, BenchmarkOperation oper, const std::string& tag
) {
    const uint32_t expected = n_reps * n_active_devs;

    coyote_thread.setCSR(reinterpret_cast<uint64_t>(buf), static_cast<uint32_t>(BenchmarkRegisters::VADDR_REG));
    coyote_thread.setCSR(chunk_size,                       static_cast<uint32_t>(BenchmarkRegisters::CHUNK_SIZE_REG));
    coyote_thread.setCSR(n_reps,                           static_cast<uint32_t>(BenchmarkRegisters::N_REPS_REG));
    coyote_thread.setCSR(0,                                static_cast<uint32_t>(BenchmarkRegisters::LBA_REG));
    coyote_thread.setCSR(dev_mask,                         static_cast<uint32_t>(BenchmarkRegisters::DEV_MASK_REG));
    coyote_thread.setCSR(DEFAULT_NSID,                     static_cast<uint32_t>(BenchmarkRegisters::NSID_REG));
    coyote_thread.setCSR(max_outstanding,                  static_cast<uint32_t>(BenchmarkRegisters::MAX_OUTSTANDING_REG));
    coyote_thread.setCSR(static_cast<uint64_t>(oper),      static_cast<uint32_t>(BenchmarkRegisters::CTRL_REG));

    while (coyote_thread.getCSR(static_cast<uint32_t>(BenchmarkRegisters::DONE_REG)) < expected) {}

    const uint64_t cycles      = coyote_thread.getCSR(static_cast<uint32_t>(BenchmarkRegisters::TIMER_REG));
    const uint16_t err         = coyote_thread.getCSR(static_cast<uint32_t>(BenchmarkRegisters::ERROR_REG)) & 0xFFFF;
    const double   seconds     = (double) cycles * (double) CLOCK_PERIOD_NS * 1e-9;
    const uint64_t total_bytes = total_size_per_dev * n_active_devs;
    const double   agg_bw      = (double) total_bytes / seconds;

    std::cout << std::setw(10) << tag
              << " | chunk=" << std::setw(8) << formatSize(chunk_size)
              << " | mask=0x" << std::hex << dev_mask << std::dec
              << " | "       << std::setw(11) << formatBW(agg_bw)
              << " | "       << cycles << " cycles"
              << " | err=0x" << std::hex << err << std::dec
              << std::endl;
}

int main(int argc, char* argv[]) {
    // CLI arguments
    std::vector<std::string> bdfs;
    std::string total_str;
    std::string chunk_str;
    std::string alloc_str;
    uint32_t max_outstanding;
    int vfpga_id;
    bool read_only;
    bool write_only;
    bool use_fpga_mem;
    bool do_verify;

    namespace po = boost::program_options;
    po::options_description runtime_options("Coyote Perf NVMe Options");
    runtime_options.add_options()
        ("bdf,b",         po::value<std::vector<std::string>>(&bdfs)->required()->multitoken(), "NVMe PCI BDF (repeat for multi-device)")
        ("total,t",       po::value<std::string>(&total_str)->default_value("64M"),             "Total transfer per device (suffixes: K/M/G)")
        ("chunk,c",       po::value<std::string>(&chunk_str)->default_value("4K"),              "Chunk size per command")
        ("alloc,a",       po::value<std::string>(&alloc_str)->default_value(""),                "NVMe allocation per device (default: total)")
        ("outstanding,o", po::value<uint32_t>(&max_outstanding)->default_value(16),             "Max outstanding commands per device")
        ("vfpga,v",       po::value<int>(&vfpga_id)->default_value(DEFAULT_VFPGA_ID),            "vFPGA ID")
        ("read-only,r",   po::bool_switch(&read_only),                                          "Run the READ benchmark only")
        ("write-only,w",  po::bool_switch(&write_only),                                         "Run the WRITE benchmark only")
        ("fpga-mem,f",    po::bool_switch(&use_fpga_mem),                                        "Place the buffer in FPGA HBM (SSD DMAs to/from HBM); default is host memory")
        ("verify,V",      po::bool_switch(&do_verify),                                            "Data integrity check: write pattern -> clear buffer -> read back -> memcmp");

    po::variables_map command_line_arguments;
    po::store(po::parse_command_line(argc, argv, runtime_options), command_line_arguments);
    po::notify(command_line_arguments);

    const uint64_t total_size = parseSize(total_str);
    const uint64_t chunk_size = parseSize(chunk_str);
    const uint64_t alloc_size = alloc_str.empty() ? total_size : parseSize(alloc_str);

    if (max_outstanding == 0 || max_outstanding >= 64) {
        throw std::runtime_error("max_outstanding must be in (0, 64); HW SQ depth is 64");
    }

    const bool do_read  = !write_only;
    const bool do_write = !read_only;

    HEADER("CLI PARAMETERS:");
    std::cout << "vFPGA ID:    " << vfpga_id << std::endl;
    std::cout << "Devices:     " << bdfs.size() << std::endl;
    std::cout << "Total/dev:   " << formatSize(total_size) << std::endl;
    std::cout << "Chunk:       " << formatSize(chunk_size) << std::endl;
    std::cout << "Outstanding: " << max_outstanding << " per device" << std::endl;
    std::cout << "Operations:  " << (do_read ? "READ " : "") << (do_write ? "WRITE" : "") << std::endl;
    std::cout << "Buffer in:   " << (use_fpga_mem ? "FPGA HBM (SSD <-> HBM P2P)" : "Host DRAM") << std::endl
              << std::endl;

    // Create the Coyote thread for this vFPGA
    coyote::cThread coyote_thread(vfpga_id, getpid());

    // Claim each NVMe device for this region
    std::vector<coyote::nvmeInitIoctl> devs;
    uint16_t dev_mask = 0;

    for (const auto& bdf : bdfs) {
        coyote::nvmeInitIoctl dev = coyote_thread.initNVMe(bdf, DEFAULT_NSID, alloc_size);
        devs.push_back(dev);
        dev_mask |= (uint16_t)(1u << dev.dev_id);
        std::cout << "  dev_id=" << dev.dev_id
                  << "  BDF=" << bdf
                  << "  lba_size=" << dev.lba_size
                  << "  nsze=" << dev.nsze
                  << "  mdts=" << dev.mdts << std::endl;
    }
    std::cout << "DEV_MASK:    0x" << std::hex << dev_mask << std::dec << std::endl;

    // Clamp the chunk to min(MDTS, PRP_CAP). No FPGA-side splitter: one user request maps
    // 1:1 to one NVMe command, whose PRP covers at most 33 pages (~128 KB).
    static constexpr uint64_t PRP_CAP = 128ULL * 1024ULL;
    uint64_t actual_chunk = chunk_size;
    if (actual_chunk > PRP_CAP) {
        std::cout << "Clamping chunk to PRP_CAP " << formatSize(PRP_CAP)
                  << " (no FPGA-side splitter)" << std::endl;
        actual_chunk = PRP_CAP;
    }
    for (const auto& dev : devs) {
        if (dev.mdts > 0 && actual_chunk > dev.mdts) {
            std::cout << "Clamping chunk to MDTS for dev " << dev.dev_id << ": "
                      << formatSize(dev.mdts) << std::endl;
            actual_chunk = dev.mdts;
        }
        if (actual_chunk < dev.lba_size || (actual_chunk % dev.lba_size) != 0) {
            for (const auto& d : devs) { coyote_thread.closeNVMe(d.dev_id); }
            throw std::runtime_error(
                "chunk size " + std::to_string(actual_chunk) +
                " is not a multiple of LBA size " + std::to_string(dev.lba_size) +
                " for dev " + std::to_string(dev.dev_id)
            );
        }
    }

    const uint32_t n_reps = (uint32_t)(total_size / actual_chunk);

    // Allocate the host buffer; populate with a pattern (so writes to the SSD have meaningful bytes)
    void* buf = coyote_thread.getMem({coyote::CoyoteAllocType::HPF, static_cast<uint32_t>(total_size)});
    if (!buf) {
        for (const auto& d : devs) { coyote_thread.closeNVMe(d.dev_id); }
        throw std::runtime_error("could not allocate host buffer");
    }
    std::memset(buf, 0xAB, total_size);

    // With --fpga-mem, offload the buffer to FPGA HBM. This re-maps the TLB so the buffer's physical
    // pages now live in card memory; the NVMe PRP entries then reference HBM and the SSD DMAs straight
    // to/from HBM (peer-to-peer) instead of host DRAM. Offload is chunked at the Coyote 128 MB limit.
    constexpr uint64_t OFFLOAD_MAX = 128ULL * 1024 * 1024;
    if (use_fpga_mem) {
        std::cout << "Offloading " << formatSize(total_size) << " to FPGA HBM..." << std::endl;
        for (uint64_t off = 0; off < total_size; off += OFFLOAD_MAX) {
            const uint64_t len = std::min(OFFLOAD_MAX, total_size - off);
            coyote_thread.invoke(coyote::CoyoteOper::LOCAL_OFFLOAD,
                                 coyote::syncSg{reinterpret_cast<uint8_t*>(buf) + off, static_cast<uint32_t>(len)});
        }
    }

    // Per-device sweep
    HEADER("PER-DEVICE BENCHMARK");
    for (const auto& dev : devs) {
        const uint16_t single_mask = (uint16_t)(1u << dev.dev_id);
        std::cout << "--- dev_id=" << dev.dev_id << " ---" << std::endl;
        if (do_write) run_bench(coyote_thread, buf, total_size, actual_chunk, n_reps, single_mask, 1, max_outstanding, BenchmarkOperation::START_WR, "WRITE");
        if (do_read)  run_bench(coyote_thread, buf, total_size, actual_chunk, n_reps, single_mask, 1, max_outstanding, BenchmarkOperation::START_RD, "READ");
    }

    // Aggregate sweep
    HEADER("ALL DEVICES TOGETHER");
    if (do_write) run_bench(coyote_thread, buf, total_size, actual_chunk, n_reps, dev_mask, (uint32_t)devs.size(), max_outstanding, BenchmarkOperation::START_WR, "WRITE");
    if (do_read)  run_bench(coyote_thread, buf, total_size, actual_chunk, n_reps, dev_mask, (uint32_t)devs.size(), max_outstanding, BenchmarkOperation::START_RD, "READ");

    // Data Integrity Verification (--verify): write pattern -> clear -> read -> memcmp.
    if (do_verify) {
        HEADER("DATA INTEGRITY VERIFY");
        uint8_t* host_buf = reinterpret_cast<uint8_t*>(buf);

        std::cout << "1. Fill buffer with pattern (i & 0xFF)... " << std::flush;
        for (uint64_t i = 0; i < total_size; i++) host_buf[i] = (uint8_t)(i & 0xFF);
        if (use_fpga_mem) {
            for (uint64_t off = 0; off < total_size; off += OFFLOAD_MAX) {
                const uint64_t len = std::min(OFFLOAD_MAX, total_size - off);
                coyote_thread.invoke(coyote::CoyoteOper::LOCAL_OFFLOAD,
                                     coyote::syncSg{host_buf + off, static_cast<uint32_t>(len)});
            }
        }
        std::cout << "OK" << std::endl;

        std::cout << "2. NVMe WRITE to SSD..." << std::endl;
        run_bench(coyote_thread, buf, total_size, actual_chunk, n_reps, dev_mask,
                  (uint32_t)devs.size(), max_outstanding, BenchmarkOperation::START_WR, "VERIFY-WR");

        std::cout << "3. Clear host buffer... " << std::flush;
        std::memset(host_buf, 0x00, total_size);
        if (use_fpga_mem) {
            for (uint64_t off = 0; off < total_size; off += OFFLOAD_MAX) {
                const uint64_t len = std::min(OFFLOAD_MAX, total_size - off);
                coyote_thread.invoke(coyote::CoyoteOper::LOCAL_OFFLOAD,
                                     coyote::syncSg{host_buf + off, static_cast<uint32_t>(len)});
            }
        }
        std::cout << "OK" << std::endl;

        std::cout << "4. NVMe READ from SSD..." << std::endl;
        run_bench(coyote_thread, buf, total_size, actual_chunk, n_reps, dev_mask,
                  (uint32_t)devs.size(), max_outstanding, BenchmarkOperation::START_RD, "VERIFY-RD");

        if (use_fpga_mem) {
            std::cout << "5. Sync HBM -> host... " << std::flush;
            for (uint64_t off = 0; off < total_size; off += OFFLOAD_MAX) {
                const uint64_t len = std::min(OFFLOAD_MAX, total_size - off);
                coyote_thread.invoke(coyote::CoyoteOper::LOCAL_SYNC,
                                     coyote::syncSg{host_buf + off, static_cast<uint32_t>(len)});
            }
            std::cout << "OK" << std::endl;
        }

        std::cout << "6. memcmp..." << std::endl;
        uint64_t errors = 0;
        uint64_t first_err_off = UINT64_MAX;
        for (uint64_t i = 0; i < total_size; i++) {
            const uint8_t expected = (uint8_t)(i & 0xFF);
            if (host_buf[i] != expected) {
                if (errors < 16) {
                    std::cout << "   MISMATCH @ 0x" << std::hex << i
                              << ": got=0x" << (int)host_buf[i]
                              << " expected=0x" << (int)expected
                              << std::dec << std::endl;
                }
                if (first_err_off == UINT64_MAX) first_err_off = i;
                errors++;
            }
        }
        if (errors == 0) {
            std::cout << "   PASS - " << formatSize(total_size) << " verified OK" << std::endl;
        } else {
            std::cout << "   FAIL - " << errors << " byte mismatches"
                      << " (first @ 0x" << std::hex << first_err_off << std::dec << ")" << std::endl;
        }
    }

    // Cleanup
    coyote_thread.freeMem(buf);
    for (const auto& d : devs) { coyote_thread.closeNVMe(d.dev_id); }

    std::cout << std::endl << "Done." << std::endl;
    return EXIT_SUCCESS;
}
