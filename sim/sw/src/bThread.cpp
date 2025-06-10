#include <filesystem>
#include <string>
#include <malloc.h>

#include "bThread.hpp"
#include "BinaryInputWriter.hpp"
#include "BinaryOutputReader.hpp"
#include "VivadoRunner.hpp"
#include "blocking_queue.hpp"

using namespace std;
using namespace std::chrono;

namespace fpga {

enum thread_ids {
    OTHER_THREAD_ID,
    SIM_THREAD_ID,
    OUT_THREAD_ID
};

typedef struct {
    uint8_t id;
    int status;
} return_t;

BinaryInputWriter input_writer;
BinaryOutputReader output_reader;
VivadoRunner vivado_runner(false);

blocking_queue<return_t> return_queue;

thread out_thread;
thread sim_thread;

int executeUnlessCrash(const std::function<void()> &lambda) {
    auto other_thread = thread([&lambda]{
        lambda();
        return_queue.push({OTHER_THREAD_ID, 0});
    });

    auto result = return_queue.pop();
    if (result.id != OTHER_THREAD_ID) { // VivadoRunner or OutputReader crashed
        LOG << "bThread: FATAL: Thread with id " << (int) result.id << " crashed" << endl;
        terminate();
    }
    other_thread.join();
    return result.status;
}

bThread::bThread(int32_t vfid, pid_t hpid, uint32_t dev, cSched *csched, void (*uisr)(int)) : vfid(vfid), hpid(hpid), csched(csched), plock(open_or_create, ("vpga_mtx_user_" + std::to_string(vfid)).c_str()) {
    std::filesystem::path sim_path(SIM_DIR);
    string input_file_name((sim_path / "input.bin").string());
    string output_file_name((sim_path / "output.bin").string());
    
    
    std::filesystem::remove(input_file_name);
    std::filesystem::remove(output_file_name);
    int status = mkfifo(input_file_name.c_str(), 0666);
    if (status == 0) status = mkfifo(output_file_name.c_str(), 0666);
    
    if (status < 0) {
        LOG << "bThread: FATAL: " << strerror(errno) << std::endl;
        terminate();
    }
    LOG << "bThread: Created named pipes input.bin and output.bin in " << SIM_DIR << std::endl;

    status = vivado_runner.openProject(SIM_DIR, "test");
    if (status == 0) status = vivado_runner.compileProject();

    if (status < 0) {
        LOG << "bThread: FATAL: Could not open or compile Vivado project" << std::endl;
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
    LOG << "bThread: Constructor(" << vfid << ", " << hpid << ", " << dev << ") finished" << std::endl;
}

bThread::~bThread() {
    // Memory: Free the memor and clear the mapped pages 
	for(auto& it: mapped_pages) {
		freeMem(it.first);
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

void setCSR(uint64_t val, uint32_t offs) {
    executeUnlessCrash([&] { 
        input_writer.setCSR(offs, val);
    });
    LOG << "bThread: setCSR(" << val << ", " << offs << ") finished" << std::endl;
}

uint64_t getCSR(uint32_t offs) {
    uint64_t result;
    executeUnlessCrash([&] { 
        input_writer.getCSR(offs);
        result = output_reader.getCSRResult();
    });
    LOG << "bThread: getCSR(" << offs << ") finished" << std::endl;
    return result;
}

// ======-------------------------------------------------------------------------------
// Schedule threads
// ======-------------------------------------------------------------------------------

void bThread::pLock(int32_t oid, uint32_t priority) {
    DBG1("Scheduling not implemented in simulation target");
    assert(false);
}

void bThread::pUnlock() {
    DBG1("Scheduling not implemented in simulation target");
    assert(false);
}

// ======-------------------------------------------------------------------------------
// Memory management
// ======-------------------------------------------------------------------------------

void bThread::userMap(void *vaddr, uint32_t len, bool remote) {
    if (remote) assert(false);

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
    if (cs_alloc.remote) assert(false);

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
                    LOG << "bThread: FATAL: Cannot obtain transparent huge pages with posix_memalign" << std::endl;
                    terminate();
                }
                userMap(mem, cs_alloc.size);

                break;
            }
            case CoyoteAlloc::HPF : {
                mem = mmap(NULL, cs_alloc.size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB, -1, 0);
                if (mem == MAP_FAILED) {
                    LOG << "bThread: FATAL: Cannot obtain huge pages with mmap" << std::endl;
                    terminate();
                }
                userMap(mem, cs_alloc.size);
				
			    break;
            }
			default: LOG << "bThread: FATAL: Alloc type unknown" << std::endl; terminate();
		}
        
        // Store the mapping in mapped_pages (pointers to memory and details of mapping as indicated in the cs_alloc struct in the beginning)
        mapped_pages.emplace(mem, cs_alloc);
        LOG << "bThread: Mapped mem at " << std::hex << reinterpret_cast<uint64_t>(mem) << std::dec << std::endl;
	}

    ((char *) mem)[0] = 1;
    LOG << "bThread: getMem(" << cs_alloc.size << ") finished" << std::endl;
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

        // mapped_pages.erase(vaddr); TODO: Why is this commented out?
	}
    LOG << "bThread: freeMem(" << reinterpret_cast<uint64_t>(vaddr) << ") finished" << std::endl;
}

// ======-------------------------------------------------------------------------------
// Bulk transfers
// ======-------------------------------------------------------------------------------

void bThread::postCmd(uint64_t offs_3, uint64_t offs_2, uint64_t offs_1, uint64_t offs_0) {
    // Do nothing because protected function
}

void bThread::invoke(CoyoteOper coper, sgEntry *sg_list, sgFlags sg_flags, uint32_t n_sg) {
    // Check whether the coyote operation can be executed given the system settings in the FPGA-configuration
    if (isRemoteRdma(coper)) {LOG << "bThread: ASSERT: Networking not implemented in simulation target!" << std::endl; assert(false);}
    if (isRemoteTcp(coper)) {LOG << "bThread: ASSERT: Networking not implemented in simulation target!" << std::endl; assert(false);}
	if (coper == CoyoteOper::NOOP) return;

    if (sg_flags.poll) {assert(false);} // This stuff doesn't work anyway if there are multiple invokes at the same time

    if (isLocalSync(coper)) { 
        // TODO: Add support for offload and sync
        LOG << "bThread: ASSERT: Offload and sync currently not supported" << std::endl;
        assert(false);
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
    LOG << "bThread: invoke(...) finished" << std::endl;
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
            LOG << "bThread: checkCompleted() passed to simulation" << std::endl;
            result = output_reader.checkCompletedResult();
        });
        return result;
	} else {
		LOG << "bThread: ASSERT: Function checkCompleted() on this CoyoteOper not supported!" << std::endl;
        assert(false);
	}
    LOG << "bThread: checkCompleted() finished" << std::endl;
}

void bThread::clearCompleted() {
    executeUnlessCrash([&] { 
        input_writer.clearCompleted();
    });
    LOG << "bThread: clearCompleted() finished" << std::endl;
}

// ======-------------------------------------------------------------------------------
// Network management
// ======-------------------------------------------------------------------------------

// Network not supported in simulation
bool bThread::doArpLookup(uint32_t ip_addr) {
    LOG << "bThread: ASSERT: Networking not implemented in simulation target" << std::endl;
    assert(false);
}

// Network not supported in simulation
bool bThread::writeQpContext(uint32_t port) {
    LOG << "bThread: ASSERT: Networking not implemented in simulation target" << std::endl;
    assert(false);
}

// Network not supported in simulation
void bThread::setConnection(int connection) {
    LOG << "bThread: ASSERT: Networking not implemented in simulation target" << std::endl;
    assert(false);
}

// Network not supported in simulation
void bThread::closeConnection() {
    LOG << "bThread: ASSERT: Networking not implemented in simulation target" << std::endl;
    assert(false);
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
    LOG << "bThread: ASSERT: Networking not implemented in simulation target" << std::endl;
    assert(false);
}

// Network not supported in simulation
void bThread::connClose(bool client) {
    LOG << "bThread: ASSERT: Networking not implemented in simulation target" << std::endl;
    assert(false);
}

// ======-------------------------------------------------------------------------------
// DEBUG
// ======-------------------------------------------------------------------------------

void bThread::printDebug() {
    // Not implemented
} 

}
