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

#include "cThread.hpp"
#include "Common.hpp"
#include "BinaryInputWriter.hpp"
#include "BinaryOutputReader.hpp"
#include "VivadoRunner.hpp"

using namespace std;
using namespace std::chrono;

namespace coyote {

BinaryInputWriter input_writer;
BinaryOutputReader output_reader([](void *data, uint64_t size){
    input_writer.writeMem(reinterpret_cast<uint64_t>(data), size, data);
});
VivadoRunner vivado_runner;

thread out_thread;
thread sim_thread;

cThread::cThread(int32_t vfid, pid_t hpid, uint32_t device, std::function<void(int)> uisr):
  hpid(hpid), vfid(vfid),
  vlock(boost::interprocess::open_or_create, ("vpga_mtx_user_" + std::to_string(std::time(nullptr))).c_str()) { // Timestamp for plock to prevent multiple users aquiring the same lock at the same time which does not matter for the simulation, only for hardware
    std::filesystem::path sim_path(SIM_DIR);
    sim_path /= "sim";
    string input_file_name((sim_path / "input.bin").string());
    string output_file_name((sim_path / "output.bin").string());
    
    
    std::filesystem::remove(input_file_name);
    std::filesystem::remove(output_file_name);
    int status = mkfifo(input_file_name.c_str(), 0666);
    if (status == 0) status = mkfifo(output_file_name.c_str(), 0666);
    
    if (status < 0) {
        FATAL(strerror(errno))
        terminate();
    }
    DEBUG("Created named pipes input.bin and output.bin in " << sim_path)

    status = vivado_runner.openProject(sim_path.c_str());
    if (status == 0) status = vivado_runner.compileProject();

    if (status < 0) {
        FATAL("Could not open or compile Vivado project")
        terminate();
    }

    // Run Vivado simulation in its own thread
    sim_thread = thread([] { 
        auto status = vivado_runner.runSimulation();
        return_queue.push({SIM_THREAD_ID, status});
    });

    output_reader.setMappedPages(&mapped_pages);
    out_thread = thread([&output_file_name] {
        auto status = output_reader.open(output_file_name.c_str());
        if (status < 0) {return_queue.push({OUT_THREAD_ID, status}); return;}
        status = output_reader.readUntilEOF();
        output_reader.close();
        return_queue.push({OUT_THREAD_ID, status});
    });

    status = executeUnlessCrash([&input_file_name] {
        input_writer.open(input_file_name.c_str());
    });

    ctid = 0; // Hardcoded for now

    // Events - check if there's a pointer provided for user-defined interrupt service routine. Only then execute the following code block. 
    if (uisr) {
        output_reader.registerIRQ(uisr);
    }

    // Clear
    clearCompleted();
    DEBUG("Constructor(" << vfid << ", " << hpid << ") finished")
}

cThread::~cThread() {
    // Memory: Free the memor and clear the mapped pages 
	while (!mapped_pages.empty()) {
		freeMem((*mapped_pages.begin()).first);
	}
	mapped_pages.clear();

    input_writer.close();

    sim_thread.join();
    out_thread.join();
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
    executeUnlessCrash([&] { 
        input_writer.userMap(reinterpret_cast<uint64_t>(vaddr), len);
    });
}

void cThread::userUnmap(void *vaddr) {
    executeUnlessCrash([&] { 
        input_writer.userUnmap(reinterpret_cast<uint64_t>(vaddr));
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
                    terminate();
                }
                userMap(mem, alloc.size);

                break;
            }
            case CoyoteAllocType::HPF : {
                mem = mmap(NULL, alloc.size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB, -1, 0);
                if (mem == MAP_FAILED) {
                    FATAL("Cannot obtain huge pages with mmap")
                    terminate();
                }
                userMap(mem, alloc.size);
				
			    break;
            }
			default: FATAL("CoyoteAllocType not supported in simulation") terminate();
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
    executeUnlessCrash([&] { 
        input_writer.setCSR(offs, val);
    });
    DEBUG("setCSR(" << val << ", " << offs << ") finished")
}

uint64_t cThread::getCSR(uint32_t offs) const {
    uint64_t result;
    executeUnlessCrash([&] { 
        input_writer.getCSR(offs);
        result = output_reader.getCSRResult();
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
        executeUnlessCrash([&] {
            input_writer.writeMem(
                reinterpret_cast<uint64_t>(sg.addr), 
                sg.len,
                sg.addr
            );
            input_writer.invoke(
                (uint8_t) CoyoteOper::LOCAL_OFFLOAD, 0, 0, 
                reinterpret_cast<uint64_t>(sg.addr), 
                sg.len, 0
            );
        });
    } else if (oper == CoyoteOper::LOCAL_SYNC) {
        executeUnlessCrash([&] {
            input_writer.invoke(
                (uint8_t) CoyoteOper::LOCAL_SYNC, 0, 0, 
                reinterpret_cast<uint64_t>(sg.addr), 
                sg.len, 0
            );
        });
    }

    executeUnlessCrash([&] { 
        input_writer.checkCompleted((uint8_t) oper, prevCompleted + 1, true);
        DEBUG("Blocking checkCompleted for sync or offload")
        output_reader.checkCompletedResult();
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
        executeUnlessCrash([&] {
            input_writer.writeMem(
                reinterpret_cast<uint64_t>(sg.addr), 
                sg.len,
                sg.addr
            );
            input_writer.invoke(
                (uint8_t) CoyoteOper::LOCAL_READ, 
                sg.stream, 
                sg.dest, 
                reinterpret_cast<uint64_t>(sg.addr), 
                sg.len,
                last
            );
        });
    } else if (isLocalWrite(oper)) {
        executeUnlessCrash([&] { 
            input_writer.invoke(
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
    executeUnlessCrash([&] {
        input_writer.writeMem(
            reinterpret_cast<uint64_t>(src_sg.addr), 
            src_sg.len,
            src_sg.addr
        );
        input_writer.invoke(
            (uint8_t) CoyoteOper::LOCAL_READ, 
            src_sg.stream, 
            src_sg.dest, 
            reinterpret_cast<uint64_t>(src_sg.addr), 
            src_sg.len,
            last
        );
    });
    executeUnlessCrash([&] { 
        input_writer.invoke(
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
    executeUnlessCrash([&] { 
        input_writer.checkCompleted((uint8_t) oper, 0, false);
        DEBUG("checkCompleted() passed to simulation")
        result = output_reader.checkCompletedResult();
    });
    DEBUG("checkCompleted() finished")
    return result;
}

void cThread::clearCompleted() {
    executeUnlessCrash([&] { 
        input_writer.clearCompleted();
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
}

void cThread::sendAck(uint32_t ack) {
    ASSERT("Networking not implemented in simulation target")
}

void cThread::connSync(bool client) {
    ASSERT("Networking not implemented in simulation target")
}

void* cThread::initRDMA(uint32_t buffer_size, uint16_t port, const char* server_address) {
    ASSERT("Networking not implemented in simulation target")
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
