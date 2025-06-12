#include <filesystem>
#include <string>
#include <malloc.h>

#include "bThread.hpp"
#include "Common.hpp"
#include "BinaryInputWriter.hpp"
#include "BinaryOutputReader.hpp"
#include "VivadoRunner.hpp"

using namespace std;
using namespace std::chrono;

namespace fpga {

BinaryInputWriter input_writer;
BinaryOutputReader output_reader([](void *data, uint64_t size){
    input_writer.writeMem(reinterpret_cast<uint64_t>(data), size, data);
});
VivadoRunner vivado_runner(false);

thread out_thread;
thread sim_thread;

bThread::bThread(int32_t vfid, pid_t hpid, uint32_t dev, cSched *csched, void (*uisr)(int)) : vfid(vfid), hpid(hpid), csched(csched), plock(open_or_create, ("vpga_mtx_user_" + std::to_string(vfid)).c_str()) {
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
    DEBUG("Constructor(" << vfid << ", " << hpid << ", " << dev << ") finished")
}

bThread::~bThread() {
    // Memory: Free the memor and clear the mapped pages 
	while (!mapped_pages.empty()) {
		freeMem((*mapped_pages.begin()).first);
	}
	mapped_pages.clear();

    input_writer.close();

    sim_thread.join();
    out_thread.join();
}

void bThread::mmapFpga() {
    // Do nothing because protected function
}

void bThread::munmapFpga() {
    // Do nothing because protected function
}

void bThread::setCSR(uint64_t val, uint32_t offs) {
    executeUnlessCrash([&] { 
        input_writer.setCSR(offs, val);
    });
    DEBUG("setCSR(" << val << ", " << offs << ") finished")
}

uint64_t bThread::getCSR(uint32_t offs) {
    uint64_t result;
    executeUnlessCrash([&] { 
        input_writer.getCSR(offs);
        result = output_reader.getCSRResult();
    });
    DEBUG("getCSR(" << offs << ") finished")
    return result;
}

// ======-------------------------------------------------------------------------------
// Schedule threads
// ======-------------------------------------------------------------------------------

void bThread::pLock(int32_t oid, uint32_t priority) {
    ASSERT("Scheduling not implemented in simulation target")
}

void bThread::pUnlock() {
    ASSERT("Scheduling not implemented in simulation target")
}

// ======-------------------------------------------------------------------------------
// Memory management
// ======-------------------------------------------------------------------------------

void bThread::userMap(void *vaddr, uint32_t len, bool remote) {
    if (remote) {ASSERT("Networking not implemented in simulation target")}

    executeUnlessCrash([&] { 
        input_writer.userMap(reinterpret_cast<uint64_t>(vaddr), len);
    });
}

void bThread::userUnmap(void *vaddr) {
    executeUnlessCrash([&] { 
        input_writer.userUnmap(reinterpret_cast<uint64_t>(vaddr));
    });
}

void* bThread::getMem(csAlloc&& cs_alloc) {
    if (cs_alloc.remote) {ASSERT("Networking not implemented in simulation target")}

	void *mem = nullptr;

    // Only continue with the operation if the cs_alloc-struct has a size > 0 so that actual memory needs to be allocated 
	if(cs_alloc.size > 0) {
		switch (cs_alloc.alloc) { // Further steps depend on the allocation type that is selected in the allocation struct 
            // Regular allocation 
			case CoyoteAlloc::REG : {
				mem = memalign(axiDataWidth, cs_alloc.size);
				userMap(mem, cs_alloc.size);
				
				break;
            }
			case CoyoteAlloc::THP : { // Allocation of transparent huge pages 
                auto mem_err = posix_memalign(&mem, hugePageSize, cs_alloc.size);
                if(mem_err != 0) {
                    FATAL("Cannot obtain transparent huge pages with posix_memalign")
                    terminate();
                }
                userMap(mem, cs_alloc.size);

                break;
            }
            case CoyoteAlloc::HPF : {
                mem = mmap(NULL, cs_alloc.size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB, -1, 0);
                if (mem == MAP_FAILED) {
                    FATAL("Cannot obtain huge pages with mmap")
                    terminate();
                }
                userMap(mem, cs_alloc.size);
				
			    break;
            }
			default: FATAL("Alloc type unknown") terminate();
		}
        
        // Store the mapping in mapped_pages (pointers to memory and details of mapping as indicated in the cs_alloc struct in the beginning)
        mapped_pages.emplace(mem, cs_alloc);
        DEBUG("Mapped mem at " << std::hex << reinterpret_cast<uint64_t>(mem) << std::dec)
	}

    ((char *) mem)[0] = 1;
    DEBUG("getMem(" << cs_alloc.size << ") finished")
	return mem;
}

void bThread::freeMem(void* vaddr) {
	if (mapped_pages.find(vaddr) != mapped_pages.end()) {
		auto mapped = mapped_pages[vaddr];
		
		switch (mapped.alloc) {
            case CoyoteAlloc::REG: case CoyoteAlloc::THP: {
                userUnmap(vaddr);
                free(vaddr);

                break;
            }
            case CoyoteAlloc::HPF : {
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

// ======-------------------------------------------------------------------------------
// Bulk transfers
// ======-------------------------------------------------------------------------------

void bThread::postCmd(uint64_t offs_3, uint64_t offs_2, uint64_t offs_1, uint64_t offs_0) {
    // Do nothing because protected function
}

void bThread::invoke(CoyoteOper coper, sgEntry *sg_list, sgFlags sg_flags, uint32_t n_sg) {
    // Check whether the coyote operation can be executed given the system settings in the FPGA-configuration
    if (isRemoteRdma(coper)) {ASSERT("Networking not implemented in simulation target!")}
    if (isRemoteTcp(coper)) {ASSERT("Networking not implemented in simulation target!")}
	if (coper == CoyoteOper::NOOP) return;

    if (sg_flags.clr) clearCompleted();

    if (isLocalSync(coper)) { 
        // TODO: Add support for offload and sync
        ASSERT("Offload and sync currently not supported")
    } else { 
        // Iterate over all entries of the scatter-gather list 
        for (int i = 0; i < n_sg; i++) { // TODO: Add support for ctid, sg_flags.clr, and sg_flags.poll
            if (isLocalRead(coper)) {
                executeUnlessCrash([&] {
                    input_writer.writeMem(
                        reinterpret_cast<uint64_t>(sg_list[i].local.src_addr), 
                        sg_list[i].local.src_len,
                        sg_list[i].local.src_addr
                    );
                    input_writer.invoke(
                        (uint8_t) CoyoteOper::LOCAL_READ, 
                        sg_list[i].local.src_stream, 
                        sg_list[i].local.src_dest, 
                        reinterpret_cast<uint64_t>(sg_list[i].local.src_addr), 
                        sg_list[i].local.src_len,
                        i == (n_sg-1) ? sg_flags.last : 0
                    );
                });
            }
            if (isLocalWrite(coper)) {
                executeUnlessCrash([&] { 
                    input_writer.invoke(
                        (uint8_t) CoyoteOper::LOCAL_WRITE, 
                        sg_list[i].local.dst_stream, 
                        sg_list[i].local.dst_dest, 
                        reinterpret_cast<uint64_t>(sg_list[i].local.dst_addr), 
                        sg_list[i].local.dst_len,
                        i == (n_sg-1) ? sg_flags.last : 0
                    );
                });
            }
        }
    }

    if(sg_flags.poll) {
        while(!checkCompleted(coper))
            std::this_thread::sleep_for(std::chrono::nanoseconds(sleepTime)); 
    }

    DEBUG("invoke(...) finished")
}

// ======-------------------------------------------------------------------------------
// Polling
// ======-------------------------------------------------------------------------------

uint32_t bThread::checkCompleted(CoyoteOper coper) {
    // Based on the type of operation, check completion via a read access to the configuration registers 
	if(isCompletedLocalRead(coper) || isCompletedLocalWrite(coper)) {
        uint32_t result;
        executeUnlessCrash([&] { 
            input_writer.checkCompleted((uint8_t) coper, 0, false);
            DEBUG("checkCompleted() passed to simulation")
            result = output_reader.checkCompletedResult();
        });
        return result;
	} else {
		ASSERT("Function checkCompleted() on this CoyoteOper not supported!")
	}
    DEBUG("checkCompleted() finished")
}

void bThread::clearCompleted() {
    executeUnlessCrash([&] { 
        input_writer.clearCompleted();
    });
    DEBUG("clearCompleted() finished")
}

// ======-------------------------------------------------------------------------------
// Network management
// ======-------------------------------------------------------------------------------

// Network not supported in simulation
bool bThread::doArpLookup(uint32_t ip_addr) {
    ASSERT("Networking not implemented in simulation target")
}

// Network not supported in simulation
bool bThread::writeQpContext(uint32_t port) {
    ASSERT("Networking not implemented in simulation target")
}

// Network not supported in simulation
void bThread::setConnection(int connection) {
    ASSERT("Networking not implemented in simulation target")
}

// Network not supported in simulation
void bThread::closeConnection() {
    ASSERT("Networking not implemented in simulation target")
}

uint32_t bThread::readAck() {
    return 0; // Do nothing because protected function
}

void bThread::sendAck(uint32_t ack) {
    // Do nothing because protected function
}

void bThread::closeAck() {
    // Do nothing because protected function
}

// Network not supported in simulation
void bThread::connSync(bool client) {
    ASSERT("Networking not implemented in simulation target")
}

// Network not supported in simulation
void bThread::connClose(bool client) {
    ASSERT("Networking not implemented in simulation target")
}

// ======-------------------------------------------------------------------------------
// DEBUG
// ======-------------------------------------------------------------------------------

void bThread::printDebug() {
    std::cout << std::setw(35) << "Sent local reads: \t-" << std::endl;
    std::cout << std::setw(35) << "Sent local writes: \t-" << std::endl;
    std::cout << std::setw(35) << "Sent remote reads: \t" << 0 << std::endl;
    std::cout << std::setw(35) << "Sent remote writes: \t" << 0 << std::endl;

    std::cout << std::setw(35) << "Invalidations received: \t-" << std::endl;
    std::cout << std::setw(35) << "Page faults received: \t-" << std::endl;
    std::cout << std::setw(35) << "Notifications received: \t-" << std::endl;	
} 

}
