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

#include <filesystem>
#include <string>
#include <malloc.h>
#include <atomic>
#include <iostream>
#include <iomanip>
#include <map>
#include <unordered_set>
#include <vector>

#include <sys/mman.h>
#include <sys/stat.h>

#include <coyote/cThread.hpp>
#include <coyote/Common.hpp>
#include <coyote/BinaryInputWriter.hpp>
#include <coyote/BinaryOutputReader.hpp>
#include <coyote/VivadoRunner.hpp>
#include <coyote/Broadcast.hpp>

namespace coyote {

class cThread::AdditionalState {
public:
    BinaryInputWriter input_writer;
    BinaryOutputReader output_reader;
    VivadoRunner vivado_runner;
    std::map<uint64_t, uint64_t> tlb_pages; // vaddr -> size of all mappings, also read by the output reader thread
    std::unordered_set<uint64_t> page_fault_mappings; // vaddrs of mappings created by handlePageFaults(...)
    std::mutex tlb_mtx; // Protects tlb_pages against concurrent reads by the output reader thread
    std::mutex map_mtx; // Serializes all mapping changes and their transfer to the simulation

    std::thread sim_thread; // Thread starting and then interacting with the Vivado process
    std::thread out_thread; // Thread running the BinaryOutputReader
    std::thread irq_thread; // Thread handling interrupts

    std::mutex get_csr_mtx;
    std::mutex check_completed_mtx;

    Broadcast<return_t> return_broadcast;
    std::atomic<size_t> thread_counter{fix_thread_ids::NUM_FIX_THREAD_IDS};

    AdditionalState() :
        input_writer(),
        output_reader(input_writer) {}

    /**
     * Executes the provided lambda until either it terminates, the simulation or output reader 
     * threads terminate, or another thread returns a non-zero status (i.e., crashes).
     */
    int executeUnlessCrash(const std::function<void()> &lambda) {
        auto last_generation = return_broadcast.register_receiver();
        size_t thread_id = thread_counter++;

        auto other_thread = std::thread([&lambda, this, thread_id] {
            lambda();
            return_broadcast.broadcast({thread_id, 0});
        });

        return_t result;
        do {
            result = return_broadcast.receive_any(last_generation);
            last_generation++;
        } while (result.id != thread_id && result.id >= fix_thread_ids::NUM_FIX_THREAD_IDS && result.status == 0);
        return_broadcast.unregister_receiver();

        if (result.id != thread_id) { // VivadoRunner or OutputReader crashed
            FATAL("Thread with id " << (int) result.id << " crashed")
            std::terminate();
        }
        other_thread.join();
        return result.status;
    }

    // Caller has to hold map_mtx
    void map(uint64_t vaddr, uint64_t len) {
        {
            std::lock_guard<std::mutex> lock(tlb_mtx);
            tlb_pages.emplace(vaddr, len);
        }
        executeUnlessCrash([&] { 
            input_writer.userMap(vaddr, len);
        });
    }

    // Caller has to hold map_mtx
    void unmap(uint64_t vaddr) {
        {
            std::lock_guard<std::mutex> lock(tlb_mtx);
            auto status = tlb_pages.erase(vaddr);
            if (status < 1) {
                ERROR("Tried to userUnmap non-existent page at vaddr " << vaddr)
            }
        }
        page_fault_mappings.erase(vaddr);
        executeUnlessCrash([&] { 
            input_writer.userUnmap(vaddr);
        });
    }

    /**
     * Emulates the page fault handling of the driver for memory that was not mapped with getMem(...) 
     * or userMap(...) before using it. Like the driver, it maps the page-aligned range around 
     * [vaddr, vaddr + len). Already mapped parts are left untouched, i.e., only the unmapped gaps are 
     * mapped. The simulation supports requests that span multiple adjacent mappings.
     */
    void handlePageFaults(const void *vaddr, uint64_t len) {
        if (len == 0) return;
        std::lock_guard<std::mutex> lock(map_mtx);

        uint64_t req_start = reinterpret_cast<uint64_t>(vaddr);
        uint64_t req_end = req_start + len;
        uint64_t start = req_start & ~(PAGE_SIZE - 1);
        uint64_t end = (req_end + PAGE_SIZE - 1) & ~(PAGE_SIZE - 1);

        // Find the gaps between the existing mappings in [start, end) that overlap with the request
        std::vector<std::pair<uint64_t, uint64_t>> gaps;
        auto add_gap = [&](uint64_t gap_start, uint64_t gap_end) {
            if (gap_start < req_end && gap_end > req_start) gaps.emplace_back(gap_start, gap_end - gap_start);
        };
        uint64_t curr = start;
        auto mapping = tlb_pages.upper_bound(start);
        if (mapping != tlb_pages.begin()) mapping--;
        for (; mapping != tlb_pages.end() && mapping->first < end; mapping++) {
            if (mapping->first > curr) add_gap(curr, mapping->first);
            curr = std::max(curr, mapping->first + mapping->second);
        }
        if (curr < end) add_gap(curr, end);

        for (auto &gap : gaps) {
            DEBUG("Page fault: Mapping vaddr " << gap.first << " with size " << gap.second)
            map(gap.first, gap.second);
            page_fault_mappings.insert(gap.first);
        }
    }

    /**
     * Removes all mappings created by handlePageFaults(...) that overlap with [vaddr, vaddr + len) 
     * so that they can be replaced by an explicit mapping. Caller has to hold map_mtx.
     */
    void unmapPageFaults(uint64_t vaddr, uint64_t len) {
        std::vector<uint64_t> overlapping;
        for (auto mapping_vaddr : page_fault_mappings) {
            if (mapping_vaddr < vaddr + len && mapping_vaddr + tlb_pages.at(mapping_vaddr) > vaddr) {
                overlapping.push_back(mapping_vaddr);
            }
        }
        for (auto mapping_vaddr : overlapping) {
            unmap(mapping_vaddr);
        }
    }
};

cThread::cThread(int32_t vfid, pid_t hpid, uint32_t device, std::function<void(int)> uisr, uint32_t timeout_ms):
  hpid(hpid), vfid(vfid), timeout_ms(timeout_ms), additional_state(std::make_unique<AdditionalState>()) {
    // Failures before the simulation threads start leave the cThread invalid (ctid = -1)
    auto raw_sim_dir = std::getenv("COYOTE_SIM_DIR");
    if (raw_sim_dir == nullptr) {
        setError(CoyoteError::NO_DEVICE, "set COYOTE_SIM_DIR to the build directory where you ran `make sim`", "cThread(vfid=", vfid, ")");
        return;
    }

    std::filesystem::path p(raw_sim_dir);
    auto sim_path = p.is_absolute() ? p : std::filesystem::current_path() / p;

    sim_path /= "sim";
    std::string input_file_name((sim_path / "input.bin").string());
    std::string output_file_name((sim_path / "output.bin").string());
    
    std::filesystem::remove(input_file_name);
    std::filesystem::remove(output_file_name);
    int status = mkfifo(input_file_name.c_str(), 0666);
    if (status == 0) status = mkfifo(output_file_name.c_str(), 0666);
    
    if (status < 0) {
        int e = errno;
        setError(errnoToError(e), strerror(e), "cThread(vfid=", vfid, ")");
        return;
    }
    DEBUG("Created named pipes input.bin and output.bin in " << sim_path)

    auto &input_writer = additional_state->input_writer;
    auto &output_reader = additional_state->output_reader;
    auto &vivado_runner = additional_state->vivado_runner;
    auto &return_broadcast = additional_state->return_broadcast;

    status = vivado_runner.openProject(sim_path.c_str());
    if (status == 0) status = vivado_runner.compileProject();

    if (status < 0) {
        setError(CoyoteError::NO_DEVICE, "could not open or compile the Vivado project", "cThread(vfid=", vfid, ")");
        return;
    }

    // Run Vivado simulation in its own thread
    additional_state->sim_thread = std::thread([&vivado_runner, &return_broadcast] { 
        auto status = vivado_runner.runSimulation();
        return_broadcast.broadcast({SIM_THREAD_ID, status});
    });

    output_reader.setTLBPages(&additional_state->tlb_pages, &additional_state->tlb_mtx);
    additional_state->out_thread = std::thread([&output_file_name, &output_reader, &return_broadcast] {
        auto status = output_reader.open(output_file_name.c_str());
        if (status < 0) {
            return_broadcast.broadcast({OUT_THREAD_ID, status}); 
            return;
        }

        status = output_reader.readUntilEOF();
        output_reader.close();
        return_broadcast.broadcast({OUT_THREAD_ID, status});
    });

    status = additional_state->executeUnlessCrash([&input_file_name, &input_writer] {
        input_writer.open(input_file_name.c_str());
    });

    ctid = 0; // Hardcoded for now

    // Events - check if there's a pointer provided for user-defined interrupt service routine
    if (uisr) {
        additional_state->irq_thread = std::thread([&output_reader, uisr] {
            bool status(true);
            uint32_t value;
            while (status) {
                status = output_reader.getNextIRQ(value);
                if (!status) {
                    DEBUG("Interrupt queue was stopped. Cannot continue interrupt handler thread!")
                    return;
                }
                uisr(value);
            }
        });
    }

    // Clear
    clearCompleted();
    DEBUG("Constructor(" << vfid << ", " << hpid << ") finished")
}

cThread::~cThread() {
    // Nothing was started for an invalid cThread
    if (!isValid()) { return; }

    // Memory: Free the memory and clear the mapped pages 
	while (!mapped_pages.empty()) {
        void* vaddr = mapped_pages.begin()->first;
		freeMem(vaddr);
        mapped_pages.erase(vaddr);
	}

    additional_state->input_writer.close();

    additional_state->sim_thread.join();
    additional_state->out_thread.join();

    if (additional_state->irq_thread.joinable())
        additional_state->irq_thread.join();
}

bool cThread::isValid() const { return ctid != -1; }

bool cThread::checkValid(const char* call) const {
    if (!isValid()) {
        printError(CoyoteError::NO_DEVICE, "the cThread is not valid, its constructor failed", "cThread::", call);
    }
    return isValid();
}

CoyoteError cThread::getLastError() const { return last_error; }

CoyoteError cThread::postCmd(uint64_t offs_3, uint64_t offs_2, uint64_t offs_1, uint64_t offs_0) {
    // Do nothing because protected function
    return CoyoteError::OK;
}

CoyoteError cThread::mmapFpga(const char*&) {
    // Do nothing because protected function
    return CoyoteError::OK;
}

void cThread::munmapFpga() noexcept {
    // Do nothing because protected function
}

CoyoteError cThread::userMap(void *vaddr, uint64_t len, int32_t mem_block) {
    if (!checkValid("userMap")) { return CoyoteError::NO_DEVICE; }
    if (mem_block != -1) {
        WARNING("Non-default values for mem_block " << mem_block << "are currently ignored");
    }
    std::lock_guard<std::mutex> lock(additional_state->map_mtx);
    // The memory might have been used before without mapping it, which caused page faults
    additional_state->unmapPageFaults(reinterpret_cast<uint64_t>(vaddr), len);
    additional_state->map(reinterpret_cast<uint64_t>(vaddr), len);
    return CoyoteError::OK;
}

CoyoteError cThread::userUnmap(void *vaddr) {
    if (!checkValid("userUnmap")) { return CoyoteError::NO_DEVICE; }
    std::lock_guard<std::mutex> lock(additional_state->map_mtx);

    // Like the driver, reject a vaddr that was never mapped (the simulation would abort on it)
    {
        std::lock_guard<std::mutex> tlb_lock(additional_state->tlb_mtx);
        if (additional_state->tlb_pages.find(reinterpret_cast<uint64_t>(vaddr)) == additional_state->tlb_pages.end()) {
            setError(CoyoteError::INVALID_ARG, nullptr, "userUnmap(vaddr=", vaddr, ")");
            return CoyoteError::INVALID_ARG;
        }
    }
    additional_state->unmap(reinterpret_cast<uint64_t>(vaddr));
    return CoyoteError::OK;
}

void* cThread::getMem(CoyoteAlloc&& alloc) {
    if (!checkValid("getMem")) { return nullptr; }
    if (alloc.remote) {
        setError(CoyoteError::NOT_SUPPORTED, "networking is not simulated", "getMem(size=", alloc.size, ")");
        return nullptr;
    }

	void *mem = nullptr;

    // Only continue with the operation if the cs_alloc-struct has a size > 0 so that actual memory needs to be allocated 
	if(alloc.size > 0) {
		switch (alloc.alloc) { // Further steps depend on the allocation type that is selected in the allocation struct 
            // Regular allocation 
			case CoyoteAllocType::REG : {
				mem = aligned_alloc(PAGE_SIZE, alloc.size);
                if (mem == nullptr) {
                    setError(CoyoteError::NO_MEMORY, nullptr, "getMem(REG, size=", alloc.size, ")");
                    return nullptr;
                }
				userMap(mem, alloc.size);
				
				break;
            }
			case CoyoteAllocType::THP : { // Allocation of transparent huge pages 
                auto mem_err = posix_memalign(&mem, HUGE_PAGE_SIZE, alloc.size);
                if(mem_err != 0) {
                    setError(errnoToError(mem_err), strerror(mem_err), "getMem(THP, size=", alloc.size, ")");
                    return nullptr;
                }
                userMap(mem, alloc.size);

                break;
            }
            case CoyoteAllocType::HPF : {
                mem = mmap(NULL, alloc.size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB, -1, 0);
                if (mem == MAP_FAILED) {
                    int e = errno;
                    setError(errnoToError(e), strerror(e), "getMem(HPF, size=", alloc.size, ")");
                    return nullptr;
                }
                userMap(mem, alloc.size);
				
			    break;
            }
			default: {
                setError(CoyoteError::NOT_SUPPORTED, "not simulated", "getMem(type=", static_cast<int>(alloc.alloc), ", size=", alloc.size, ")");
                return nullptr;
            }
		}
        
        // Store the mapping in mapped_pages (pointers to memory and details of mapping as indicated in the cs_alloc struct in the beginning)
        mapped_pages.emplace(mem, alloc);
        DEBUG("Mapped mem at " << std::hex << reinterpret_cast<uint64_t>(mem) << std::dec)
	} else {
        setError(CoyoteError::INVALID_ARG, nullptr, "getMem(size=0)");
        return nullptr;
    }

    ((char *) mem)[0] = 1;
    DEBUG("getMem(" << alloc.size << ") finished")
	return mem;
}

CoyoteError cThread::freeMem(void* vaddr) {
    if (!checkValid("freeMem")) { return CoyoteError::NO_DEVICE; }
	if (mapped_pages.find(vaddr) != mapped_pages.end()) {
		auto mapped = mapped_pages[vaddr];
		
		switch (mapped.alloc) {
            case CoyoteAllocType::REG: case CoyoteAllocType::THP: {
                userUnmap(vaddr);
                free(vaddr);

                break;
            }
            case CoyoteAllocType::HPF: {
                userUnmap(vaddr);
                munmap(vaddr, mapped.size);

                break;
            }
            default: break;
		}

        mapped_pages.erase(vaddr);
        DEBUG("freeMem(" << reinterpret_cast<uint64_t>(vaddr) << ") finished")
        return CoyoteError::OK;
	}

    setError(CoyoteError::INVALID_ARG, "not allocated with getMem", "freeMem(vaddr=", vaddr, ")");
    return CoyoteError::INVALID_ARG;
}

void cThread::setCSR(uint64_t val, uint32_t offs) {
    if (!checkValid("setCSR")) { return; }
    additional_state->executeUnlessCrash([&] { 
        additional_state->input_writer.setCSR(offs, val);
    });
    DEBUG("setCSR(" << val << ", " << offs << ") finished")
}

uint64_t cThread::getCSR(uint32_t offs) const {
    if (!checkValid("getCSR")) { return 0; }
    uint64_t result;
    additional_state->executeUnlessCrash([&] {
        // We need to lock here because otherwise we cannot guarantee ordering of results
        std::lock_guard<std::mutex> lock(additional_state->get_csr_mtx);
        
        additional_state->input_writer.getCSR(offs);
        result = additional_state->output_reader.getCSRResult();
    });
    DEBUG("getCSR(" << offs << ") finished")
    return result;
}

CoyoteError cThread::invoke(CoyoteOper oper, syncSg sg) {
    DEBUG("cThread: Call invoke for a sync/offload operation with address " << sg.addr << ", length " << sg.len)
    if (!checkValid("invoke")) { return CoyoteError::NO_DEVICE; }
    
    // Argument checks
    if (!isLocalSync(oper)) {
        setError(CoyoteError::INVALID_ARG, "syncSg requires LOCAL_SYNC or LOCAL_OFFLOAD", "invoke(oper=", static_cast<int>(oper), ", addr=", sg.addr, ", len=", sg.len, ")");
        return CoyoteError::INVALID_ARG;
    }

    if (sg.len > MAX_TRANSFER_SIZE) {
        setError(CoyoteError::INVALID_ARG, "transfers over 128 MB are not supported", "invoke(oper=", static_cast<int>(oper), ", addr=", sg.addr, ", len=", sg.len, ")");
        return CoyoteError::INVALID_ARG;
    }

    additional_state->handlePageFaults(sg.addr, sg.len);

    auto prevCompleted = checkCompleted(oper);

    // Trigger the operation
    if (oper == CoyoteOper::LOCAL_OFFLOAD) {
        additional_state->executeUnlessCrash([&] {
            additional_state->input_writer.writeMem(
                reinterpret_cast<uint64_t>(sg.addr), 
                sg.len,
                sg.addr
            );
            additional_state->input_writer.invoke(
                (uint8_t) CoyoteOper::LOCAL_OFFLOAD, 0, 0, 
                reinterpret_cast<uint64_t>(sg.addr), 
                sg.len, 0
            );
        });
    } else if (oper == CoyoteOper::LOCAL_SYNC) {
        additional_state->executeUnlessCrash([&] {
            additional_state->input_writer.invoke(
                (uint8_t) CoyoteOper::LOCAL_SYNC, 0, 0, 
                reinterpret_cast<uint64_t>(sg.addr), 
                sg.len, 0
            );
        });
    }

    additional_state->executeUnlessCrash([&] { 
        additional_state->input_writer.checkCompleted((uint8_t) oper, prevCompleted + 1, true);
        DEBUG("Blocking checkCompleted for sync or offload")
        additional_state->output_reader.checkCompletedResult();
    });

    DEBUG("invoke(...) finished")
    return CoyoteError::OK;
}

CoyoteError cThread::invoke(CoyoteOper oper, localSg sg, bool last) {
    // Argument checks
    DEBUG("cThread: Call invoke for a one-side local operation with address " << sg.addr << ", length " << sg.len)
    if (!checkValid("invoke")) { return CoyoteError::NO_DEVICE; }

    if (oper != CoyoteOper::LOCAL_READ && oper != CoyoteOper::LOCAL_WRITE) {
        setError(CoyoteError::INVALID_ARG, "localSg requires LOCAL_READ or LOCAL_WRITE", "invoke(oper=", static_cast<int>(oper), ", addr=", sg.addr, ", len=", sg.len, ")");
        return CoyoteError::INVALID_ARG;
    }

    if (sg.len > MAX_TRANSFER_SIZE) {
        setError(CoyoteError::INVALID_ARG, "transfers over 128 MB are not supported", "invoke(oper=", static_cast<int>(oper), ", addr=", sg.addr, ", len=", sg.len, ")");
        return CoyoteError::INVALID_ARG;
    }

    additional_state->handlePageFaults(sg.addr, sg.len);

    // Trigger the operation
    if (isLocalRead(oper)) {
        additional_state->executeUnlessCrash([&] {
            additional_state->input_writer.writeMem(
                reinterpret_cast<uint64_t>(sg.addr), 
                sg.len,
                sg.addr
            );
            additional_state->input_writer.invoke(
                (uint8_t) CoyoteOper::LOCAL_READ, 
                sg.stream, 
                sg.dest, 
                reinterpret_cast<uint64_t>(sg.addr), 
                sg.len,
                last
            );
        });
    } else if (isLocalWrite(oper)) {
        additional_state->executeUnlessCrash([&] { 
            additional_state->input_writer.invoke(
                (uint8_t) CoyoteOper::LOCAL_WRITE, 
                sg.stream, 
                sg.dest, 
                reinterpret_cast<uint64_t>(sg.addr), 
                sg.len,
                last
            );
        });
    }

    DEBUG("invoke(...) finished")
    return CoyoteError::OK;
}

CoyoteError cThread::invoke(CoyoteOper oper, localSg src_sg, localSg dst_sg, bool last) {
    // Argument checks
    DEBUG(
        "cThread: Call invoke for a two-sided local operation with source address " 
        << src_sg.addr << ", source length " << src_sg.len << "destination address "
        << dst_sg.addr << ", destination length " << dst_sg.len
    )
    if (!checkValid("invoke")) { return CoyoteError::NO_DEVICE; }

    if (oper != CoyoteOper::LOCAL_TRANSFER) {
        setError(
            CoyoteError::INVALID_ARG, "two localSg require LOCAL_TRANSFER", "invoke(oper=", static_cast<int>(oper),
            ", src=", src_sg.addr, ", src_len=", src_sg.len, ", dst=", dst_sg.addr, ", dst_len=", dst_sg.len, ")"
        );
        return CoyoteError::INVALID_ARG;
    }

    if (src_sg.len > MAX_TRANSFER_SIZE || dst_sg.len > MAX_TRANSFER_SIZE) {
        setError(
            CoyoteError::INVALID_ARG, "transfers over 128 MB are not supported", "invoke(oper=", static_cast<int>(oper),
            ", src=", src_sg.addr, ", src_len=", src_sg.len, ", dst=", dst_sg.addr, ", dst_len=", dst_sg.len, ")"
        );
        return CoyoteError::INVALID_ARG;
    }

    additional_state->handlePageFaults(src_sg.addr, src_sg.len);
    additional_state->handlePageFaults(dst_sg.addr, dst_sg.len);

    // Trigger the operation
    additional_state->executeUnlessCrash([&] {
        additional_state->input_writer.writeMem(
            reinterpret_cast<uint64_t>(src_sg.addr), 
            src_sg.len,
            src_sg.addr
        );
        additional_state->input_writer.invoke(
            (uint8_t) CoyoteOper::LOCAL_READ, 
            src_sg.stream, 
            src_sg.dest, 
            reinterpret_cast<uint64_t>(src_sg.addr), 
            src_sg.len,
            last
        );
    });
    additional_state->executeUnlessCrash([&] { 
        additional_state->input_writer.invoke(
            (uint8_t) CoyoteOper::LOCAL_WRITE, 
            dst_sg.stream, 
            dst_sg.dest, 
            reinterpret_cast<uint64_t>(dst_sg.addr), 
            dst_sg.len,
            last
        );
    });
    return CoyoteError::OK;
}

CoyoteError cThread::invoke(CoyoteOper oper, rdmaSg sg, bool last) {
    if (!checkValid("invoke")) { return CoyoteError::NO_DEVICE; }
    setError(CoyoteError::NOT_SUPPORTED, "networking is not simulated", "invoke(oper=", static_cast<int>(oper), ", len=", sg.len, ")");
    return CoyoteError::NOT_SUPPORTED;
}

CoyoteError cThread::invoke(CoyoteOper oper, tcpSg sg, bool last) {
    if (!checkValid("invoke")) { return CoyoteError::NO_DEVICE; }
    setError(CoyoteError::NOT_SUPPORTED, "networking is not simulated", "invoke(oper=", static_cast<int>(oper), ", len=", sg.len, ")");
    return CoyoteError::NOT_SUPPORTED;
}

uint32_t cThread::checkCompleted(CoyoteOper oper) const {
    // Networking is not simulated, so no remote operation ever completes
    if (!checkValid("checkCompleted") || isRemoteRdma(oper) || isRemoteTcp(oper)) { return 0; }

    // Based on the type of operation, check completion via a read access to the configuration registers 
    uint32_t result;
    additional_state->executeUnlessCrash([&] { 
        // We need to lock here because otherwise we cannot guarantee ordering of results
        std::lock_guard<std::mutex> lock(additional_state->check_completed_mtx);

        additional_state->input_writer.checkCompleted((uint8_t) oper, 0, false);
        DEBUG("checkCompleted() passed to simulation")
        result = additional_state->output_reader.checkCompletedResult();
    });
    DEBUG("checkCompleted() finished")
    return result;
}

void cThread::clearCompleted() {
    if (!checkValid("clearCompleted")) { return; }
    additional_state->executeUnlessCrash([&] { 
        additional_state->input_writer.clearCompleted();
    });
    DEBUG("clearCompleted() finished")
}

// Networking is not simulated
void cThread::doArpLookup(uint32_t ip_addr) {}

void cThread::writeQpContext(uint32_t port) {}
 
CoyoteError cThread::readAck(uint32_t& ack) {
    return CoyoteError::NOT_SUPPORTED;
}

CoyoteError cThread::sendAck(uint32_t ack) {
    return CoyoteError::NOT_SUPPORTED;
}

CoyoteError cThread::connSync(bool client) {
    if (!checkValid("connSync")) { return CoyoteError::NO_DEVICE; }
    setError(CoyoteError::NOT_SUPPORTED, "networking is not simulated", "connSync(client=", client, ")");
    return CoyoteError::NOT_SUPPORTED;
}

void* cThread::initRDMA(uint64_t buffer_size, uint16_t port, const char* server_address, void* mem) {
    if (!checkValid("initRDMA")) { return nullptr; }
    setError(CoyoteError::NOT_SUPPORTED, "networking is not simulated", "initRDMA(size=", buffer_size, ", port=", port, ")");
    return nullptr;
}

void cThread::closeConn() {}

// The simulation has a single cThread with exclusive access to the vFPGA
CoyoteError cThread::lock() {
    if (!checkValid("lock")) { return CoyoteError::NO_DEVICE; }
    lock_acquired = true;
    return CoyoteError::OK;
}

CoyoteError cThread::unlock() {
    if (!checkValid("unlock")) { return CoyoteError::NO_DEVICE; }
    lock_acquired = false;
    return CoyoteError::OK;
}

int32_t cThread::getVfid() const { return vfid;};

int32_t cThread::getCtid() const { return ctid; };

pid_t  cThread::getHpid() const { return hpid; };

ibvQp* cThread::getQpair() const { return qpair.get(); }

void cThread::printDebug() const {
    if (!checkValid("printDebug")) { return; }
    std::cout << std::setw(35) << "Sent local reads: \t-" << std::endl;
    std::cout << std::setw(35) << "Sent local writes: \t-" << std::endl;
    std::cout << std::setw(35) << "Sent remote reads: \t" << 0 << std::endl;
    std::cout << std::setw(35) << "Sent remote writes: \t" << 0 << std::endl;

    std::cout << std::setw(35) << "Invalidations received: \t-" << std::endl;
    std::cout << std::setw(35) << "Page faults received: \t-" << std::endl;
    std::cout << std::setw(35) << "Notifications received: \t-" << std::endl;	
} 

}
