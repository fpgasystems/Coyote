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
    std::unordered_map<void *, uint32_t> tlb_pages;

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
};

cThread::cThread(int32_t vfid, pid_t hpid, uint32_t device, std::function<void(int)> uisr):
  hpid(hpid), vfid(vfid),
  vlock(boost::interprocess::open_or_create, ("vpga_mtx_user_" + std::to_string(std::time(nullptr))).c_str()),
  additional_state(std::make_unique<AdditionalState>()) { // Timestamp for plock to prevent multiple users aquiring the same lock at the same time which does not matter for the simulation, only for hardware
    auto raw_sim_dir = std::getenv("COYOTE_SIM_DIR");
    if (raw_sim_dir == nullptr) {
        FATAL("you must set the COYOTE_SIM_DIR environment variable to the directory "
              "build directory where you ran `make sim` (usually, build_hw)")
        std::terminate();
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
        FATAL(strerror(errno))
        std::terminate();
    }
    DEBUG("Created named pipes input.bin and output.bin in " << sim_path)

    auto &input_writer = additional_state->input_writer;
    auto &output_reader = additional_state->output_reader;
    auto &vivado_runner = additional_state->vivado_runner;
    auto &return_broadcast = additional_state->return_broadcast;

    status = vivado_runner.openProject(sim_path.c_str());
    if (status == 0) status = vivado_runner.compileProject();

    if (status < 0) {
        FATAL("Could not open or compile Vivado project")
        std::terminate();
    }

    // Run Vivado simulation in its own thread
    additional_state->sim_thread = std::thread([&vivado_runner, &return_broadcast] { 
        auto status = vivado_runner.runSimulation();
        return_broadcast.broadcast({SIM_THREAD_ID, status});
    });

    output_reader.setTLBPages(&additional_state->tlb_pages);
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
    // Memory: Free the memory and clear the mapped pages 
	while (!mapped_pages.empty()) {
		freeMem((*mapped_pages.begin()).first);
	}
	mapped_pages.clear();

    additional_state->input_writer.close();

    additional_state->sim_thread.join();
    additional_state->out_thread.join();

    if (additional_state->irq_thread.joinable())
        additional_state->irq_thread.join();
}

void cThread::postCmd(uint64_t offs_3, uint64_t offs_2, uint64_t offs_1, uint64_t offs_0) {
    // Do nothing because protected function
}

void cThread::mmapFpga() {
    // Do nothing because protected function
}

void cThread::munmapFpga() {
    // Do nothing because protected function
}

void cThread::userMap(void *vaddr, uint32_t len) {
    additional_state->tlb_pages.emplace(vaddr, len);
    additional_state->executeUnlessCrash([&] { 
        additional_state->input_writer.userMap(reinterpret_cast<uint64_t>(vaddr), len);
    });
}

void cThread::userUnmap(void *vaddr) {
    auto status = additional_state->tlb_pages.erase(vaddr);
    if (status < 1) {
        ERROR("Tried to userUnmap non-existent page at vaddr " << vaddr)
    }
    additional_state->executeUnlessCrash([&] { 
        additional_state->input_writer.userUnmap(reinterpret_cast<uint64_t>(vaddr));
    });
}

void* cThread::getMem(CoyoteAlloc&& alloc) {
    if (alloc.remote) {ASSERT("Networking not implemented in simulation target")}

	void *mem = nullptr;

    // Only continue with the operation if the cs_alloc-struct has a size > 0 so that actual memory needs to be allocated 
	if(alloc.size > 0) {
		switch (alloc.alloc) { // Further steps depend on the allocation type that is selected in the allocation struct 
            // Regular allocation 
			case CoyoteAllocType::REG : {
				mem = aligned_alloc(PAGE_SIZE, alloc.size);
				userMap(mem, alloc.size);
				
				break;
            }
			case CoyoteAllocType::THP : { // Allocation of transparent huge pages 
                auto mem_err = posix_memalign(&mem, HUGE_PAGE_SIZE, alloc.size);
                if(mem_err != 0) {
                    FATAL("Cannot obtain transparent huge pages with posix_memalign")
                    std::terminate();
                }
                userMap(mem, alloc.size);

                break;
            }
            case CoyoteAllocType::HPF : {
                mem = mmap(NULL, alloc.size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB, -1, 0);
                if (mem == MAP_FAILED) {
                    FATAL("Cannot obtain huge pages with mmap")
                    std::terminate();
                }
                userMap(mem, alloc.size);
				
			    break;
            }
			default: FATAL("CoyoteAllocType not supported in simulation") std::terminate();
		}
        
        // Store the mapping in mapped_pages (pointers to memory and details of mapping as indicated in the cs_alloc struct in the beginning)
        mapped_pages.emplace(mem, alloc);
        DEBUG("Mapped mem at " << std::hex << reinterpret_cast<uint64_t>(mem) << std::dec)
	}

    ((char *) mem)[0] = 1;
    DEBUG("getMem(" << alloc.size << ") finished")
	return mem;
}

void cThread::freeMem(void* vaddr) {
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
	}
    DEBUG("freeMem(" << reinterpret_cast<uint64_t>(vaddr) << ") finished")
}

void cThread::setCSR(uint64_t val, uint32_t offs) {
    additional_state->executeUnlessCrash([&] { 
        additional_state->input_writer.setCSR(offs, val);
    });
    DEBUG("setCSR(" << val << ", " << offs << ") finished")
}

uint64_t cThread::getCSR(uint32_t offs) const {
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

void cThread::invoke(CoyoteOper oper, syncSg sg) {
    DEBUG("cThread: Call invoke for a sync/offload operation with address " << sg.addr << ", length " << sg.len)
    
    // Argument checks
    if (!isLocalSync(oper)) {
        throw std::runtime_error("ERROR: cThread::invoke() called with syncSg flags, but the operation is not a LOCAL_SYNC or LOCAL_OFFLOAD; exiting...");
    }

    if (sg.len > MAX_TRANSFER_SIZE) {
        throw std::runtime_error("ERROR: cThread::invoke() - transfers over 128MB are currently not supported in Coyote, exiting...");
    }

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
}

void cThread::invoke(CoyoteOper oper, localSg sg, bool last) {
    // Argument checks
    DEBUG("cThread: Call invoke for a one-side local operation with address " << sg.addr << ", length " << sg.len)

    if (!isLocalRead(oper) && !isLocalWrite(oper)) {
        throw std::runtime_error("ERROR: cThread::invoke() called with localSg flags, but the operation is not a LOCAL_READ or LOCAL_WRITE; exiting...");
    }

    if (sg.len > MAX_TRANSFER_SIZE) {
        throw std::runtime_error("ERROR: cThread::invoke() - transfers over 128MB are currently not supported in Coyote, exiting...");
    }

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
}

void cThread::invoke(CoyoteOper oper, localSg src_sg, localSg dst_sg, bool last) {
    // Argument checks
    DEBUG(
        "cThread: Call invoke for a two-sided local operation with source address " 
        << src_sg.addr << ", source length " << src_sg.len << "destination address "
        << dst_sg.addr << ", destination length " << dst_sg.len
    )

    if (!(isLocalRead(oper) && isLocalWrite(oper))) {
        throw std::runtime_error("ERROR: cThread::invoke() called with two localSg flags, but the operation is not a LOCAL_TRANSFER; exiting...");
    }

    if (src_sg.len > MAX_TRANSFER_SIZE || dst_sg.len > MAX_TRANSFER_SIZE) {
        throw std::runtime_error("ERROR: cThread::invoke() - transfers over 128MB are currently not supported in Coyote, exiting...");
    }

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
}

void cThread::invoke(CoyoteOper oper, rdmaSg sg, bool last) {
    ASSERT("Networking not implemented in simulation target!")
}

void cThread::invoke(CoyoteOper oper, tcpSg sg, bool last) {
    ASSERT("Networking not implemented in simulation target!")
}

uint32_t cThread::checkCompleted(CoyoteOper oper) const {
    if (isRemoteRdma(oper)) {ASSERT("Networking not implemented in simulation target!")}
    if (isRemoteTcp(oper)) {ASSERT("Networking not implemented in simulation target!")}

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
    additional_state->executeUnlessCrash([&] { 
        additional_state->input_writer.clearCompleted();
    });
    DEBUG("clearCompleted() finished")
}

void cThread::doArpLookup(uint32_t ip_addr) {
    ASSERT("Networking not implemented in simulation target")
}

void cThread::writeQpContext(uint32_t port) {
    ASSERT("Networking not implemented in simulation target")
}
 
uint32_t cThread::readAck() {
    ASSERT("Networking not implemented in simulation target")
    return 0;
}

void cThread::sendAck(uint32_t ack) {
    ASSERT("Networking not implemented in simulation target")
}

void cThread::connSync(bool client) {
    ASSERT("Networking not implemented in simulation target")
}

void* cThread::initRDMA(uint32_t buffer_size, uint16_t port, const char* server_address) {
    ASSERT("Networking not implemented in simulation target")
    return nullptr;
}

void cThread::closeConn() {
    ASSERT("Networking not implemented in simulation target")
}

void cThread::lock() {
    ASSERT("Scheduling not implemented in simulation target")
}

void cThread::unlock() {
    ASSERT("Scheduling not implemented in simulation target")
}

int32_t cThread::getVfid() const { return vfid;};

int32_t cThread::getCtid() const { return ctid; };

pid_t  cThread::getHpid() const { return hpid; };

ibvQp* cThread::getQpair() const { return qpair.get(); }

void cThread::printDebug() const {
    std::cout << std::setw(35) << "Sent local reads: \t-" << std::endl;
    std::cout << std::setw(35) << "Sent local writes: \t-" << std::endl;
    std::cout << std::setw(35) << "Sent remote reads: \t" << 0 << std::endl;
    std::cout << std::setw(35) << "Sent remote writes: \t" << 0 << std::endl;

    std::cout << std::setw(35) << "Invalidations received: \t-" << std::endl;
    std::cout << std::setw(35) << "Page faults received: \t-" << std::endl;
    std::cout << std::setw(35) << "Notifications received: \t-" << std::endl;	
} 

}
