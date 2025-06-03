#include "bThread.hpp"
#include "BinaryInputWriter.hpp"
#include "BinaryOutputReader.hpp"

using namespace std::chrono;

namespace fpga {
BinaryInputWriter  input_writer;
BinaryOutputReader output_reader;

bThread::bThread(int32_t vfid, pid_t hpid, uint32_t dev, cSched *csched, void (*uisr)(int)) : vfid(vfid), hpid(hpid), csched(csched), plock(open_or_create, ("vpga_mtx_user_" + std::to_string(vfid)).c_str()) {
    char input_file_name[] = "/local/home/jodann/coyote_fork/sim/input.bin";
    char output_file_name[] = "/local/home/jodann/coyote_fork/sim/output.bin";
    
    mkfifo(input_file_name, 0666);
    mkfifo(output_file_name, 0666);

    input_writer.open(input_file_name);
    output_reader.open(output_file_name);

	ctid = 0; // Hardcoded for now

    // Events - check if there's a pointer provided for user-defined interrupt service routine. Only then execute the following code block. 
    if (uisr) {
        // Register the interrupt handler with the output reader.
		// TODO:
	}

	// Clear
	clearCompleted();
}

bThread::~bThread() {
    input_writer.close();
    output_reader.close();
}

void bThread::mmapFpga() {
    // Do nothing because protected function
}

void bThread::munmapFpga() {
    // Do nothing because protected function
}

void setCSR(uint64_t val, uint32_t offs) {
    input_writer.setCSR(offs, val); 
}

uint64_t getCSR(uint32_t offs) {
    input_writer.getCSR(offs);
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

void bThread::userMap(void *vaddr, uint32_t len, bool remote) { // TODO: Implement memory allocation stuff
    // tmp holds the three relevant variables of vaddr, lenght and ctid for this mapping
    uint64_t tmp[maxUserCopyVals];
    tmp[0] = reinterpret_cast<uint64_t>(vaddr);
    tmp[1] = static_cast<uint64_t>(len);
    tmp[2] = static_cast<uint64_t>(ctid);

    # ifdef VERBOSE
        std::cout << "bThread: Called userMap to map user-defined memory at vaddr " << vaddr << ", length " << len << " and ctid " << ctid << "." << std::endl; 
    # endif

    // Map to the memory space 
    if(ioctl(fd, IOCTL_MAP_USER, &tmp))
        throw std::runtime_error("ioctl_map_user() failed");

    // If remote is set, the information about the vaddr and length of the memory are attached to the qpair
    if(remote) {
        qpair->local.vaddr = vaddr;
        qpair->local.size = len;

        is_buff_attached = true;
    }
}

void bThread::userUnmap(void *vaddr) {

    # ifdef VERBOSE
        std::cout << "bThread: Called userUnmap to free user-defined memory." << std::endl; 
    # endif

	uint64_t tmp[maxUserCopyVals];
	tmp[0] = reinterpret_cast<uint64_t>(vaddr);
	tmp[1] = static_cast<uint64_t>(ctid);

    if(ioctl(fd, IOCTL_UNMAP_USER, &tmp)) 
        throw std::runtime_error("ioctl_unmap_user() failed");
}

void* bThread::getMem(csAlloc&& cs_alloc) {

    # ifdef VERBOSE
        std::cout << "bThread: Called getMem to obtain memory at size " << cs_alloc.size << std::endl; 
    # endif

	void *mem = nullptr;
	void *memNonAligned = nullptr;
    int mem_err;
	uint64_t tmp[maxUserCopyVals];

    // Only continue with the operation if the cs_alloc-struct has a size > 0 so that actual memory needs to be allocated 
	if(cs_alloc.size > 0) {
        // Set tmp-variable to size of the desired allocation 
		tmp[0] = static_cast<uint64_t>(cs_alloc.size);

        // Further steps depend on the allocation type that is selected in the allocation struct 
		switch (cs_alloc.alloc) 
        {
            // Regular allocation 
			case CoyoteAlloc::REG : { // drv lock
                # ifdef VERBOSE
                    std::cout << "bThread: Obtain regular memory." << std::endl; 
                # endif

				mem = memalign(axiDataWidth, cs_alloc.size);
				userMap(mem, cs_alloc.size);
				
				break;
            }

            // Allocation of transparent huge pages 
			case CoyoteAlloc::THP : { // drv lock
                # ifdef VERBOSE
                    std::cout << "bThread: Obtain THP memory." << std::endl; 
                # endif

                mem_err = posix_memalign(&mem, hugePageSize, cs_alloc.size);
                if(mem_err != 0) {
                    DBG1("ERR:  Failed to allocate transparent hugepages!");
                    return nullptr;
                }
                userMap(mem, cs_alloc.size);

                break;
            }

            case CoyoteAlloc::HPF : { // drv lock
                # ifdef VERBOSE
                    std::cout << "bThread: Obtain HPF memory (Huge Page)." << std::endl; 
                # endif

                mem = mmap(NULL, cs_alloc.size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB, -1, 0);
                userMap(mem, cs_alloc.size);
				
			    break;
            }

			default:
				break;
		}
        
        // Store the mapping in mapped_pages (pointers to memory and details of mapping as indicated in the cs_alloc struct in the beginning)
        mapped_pages.emplace(mem, cs_alloc);
		DBG3("Mapped mem at: " << std::hex << reinterpret_cast<uint64_t>(mem) << std::dec);

        // If cs_alloc indicated memory allocation for remote memory, then add vaddr and lenght of the allocated memory to the qpair descriptor 
        if(cs_alloc.remote) {
            # ifdef VERBOSE
                std::cout << "bThread: Allocation-type is remote, so QP is equipped with the vaddr " << mem << " and is of size " << cs_alloc.size << std::endl; 
            # endif
            qpair->local.vaddr = mem;
            qpair->local.size =  cs_alloc.size;  

            is_buff_attached = true;
        }

	}

	return mem;
}

void bThread::freeMem(void* vaddr) {
	uint64_t tmp[maxUserCopyVals];
    uint32_t n_pages;
	uint32_t size;

	if(mapped_pages.find(vaddr) != mapped_pages.end()) {
		auto mapped = mapped_pages[vaddr];
		
		switch (mapped.alloc) 
        {
            case CoyoteAlloc::REG : { // drv lock
                userUnmap(vaddr);
                free(vaddr);

                break;
            }
            case CoyoteAlloc::THP : { // drv lock
                //size = mapped.size * (1 << hugePageShift);
                userUnmap(vaddr);
                free(vaddr);

                break;
            }
            case CoyoteAlloc::HPF : { // drv lock
                //size = mapped.size * (1 << hugePageShift);
                userUnmap(vaddr);
                munmap(vaddr, mapped.size);

                break;
            }
            default:
                break;
		}

	    // mapped_pages.erase(vaddr);

        if(mapped.remote) {
            qpair->local.vaddr = 0;
            qpair->local.size =  0;  

            is_buff_attached = false;
        }
	}
}

// ======-------------------------------------------------------------------------------
// Bulk transfers
// ======-------------------------------------------------------------------------------

void bThread::postCmd(uint64_t offs_3, uint64_t offs_2, uint64_t offs_1, uint64_t offs_0) {
    // Do nothing because protected function
}

void bThread::invoke(CoyoteOper coper, sgEntry *sg_list, sgFlags sg_flags, uint32_t n_sg) {
    // Check whether the coyote operation can be executed given the system settings in the FPGA-configuration
    if(isRemoteRdma(coper)) {DBG1("Networking not implemented in simulation target!"); assert(false);}
    if(isRemoteTcp(coper)) {DBG1("Networking not implemented in simulation target!"); assert(false);}
	if(coper == CoyoteOper::NOOP) return;

    if(isLocalSync(coper)) { 
        // TODO: Add support for offload and sync
        DBG1("Offload and sync currently not supported");
        assert(false);
    } else { 
        // Iterate over all entries of the scatter-gather list 
        for(int i = 0; i < n_sg; i++) { // TODO: Add support for ctid and sg_flags.clr
            if (isLocalRead(coper)) {
                input_writer.invoke(
                    (uint8_t) CoyoteOper::LOCAL_READ, 
                    sg_list[i].local.src_stream, 
                    sg_list[i].local.src_dest, 
                    reinterpret_cast<uint64_t>(sg_list[i].local.src_addr), 
                    sg_list[i].local.src_len,
                    i == (n_sg-1) ? sg_flags.last : 0
                );
            }

            if (isLocalWrite(coper)) {
                input_writer.invoke(
                    (uint8_t) CoyoteOper::LOCAL_WRITE, 
                    sg_list[i].local.dst_stream, 
                    sg_list[i].local.dst_dest, 
                    reinterpret_cast<uint64_t>(sg_list[i].local.dst_addr), 
                    sg_list[i].local.dst_len,
                    i == (n_sg-1) ? sg_flags.last : 0
                );
            }
        }

        // Polling
        if(sg_flags.poll) {
            while(!checkCompleted(coper))
                std::this_thread::sleep_for(std::chrono::nanoseconds(sleepTime)); 
        }
    }
}

// ======-------------------------------------------------------------------------------
// Polling
// ======-------------------------------------------------------------------------------

uint32_t bThread::checkCompleted(CoyoteOper coper) {
    // Based on the type of operation, check completion via a read access to the configuration registers 

	if(isCompletedLocalRead(coper) || isCompletedLocalWrite(coper)) {
		input_writer.checkCompleted((uint8_t) coper, 0, 0);
        return output_reader.; // TODO: Implement output reader
	} else {
		DBG1("Function checkCompleted() on this CoyoteOper not supported!");
        assert(false);
	}
}

void bThread::clearCompleted() { // TODO: Implement this in simulation
    cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::CTRL_REG_2)] = CTRL_CLR_STAT | ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS);
    cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::CTRL_REG)] = CTRL_CLR_STAT | ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS);
}

// ======-------------------------------------------------------------------------------
// Network management
// ======-------------------------------------------------------------------------------

// Network not supported in simulation
bool bThread::doArpLookup(uint32_t ip_addr) {
    DBG1("Networking not implemented in simulation target");
    assert(false);
}

// Network not supported in simulation
bool bThread::writeQpContext(uint32_t port) {
    DBG1("Networking not implemented in simulation target");
    assert(false);
}

// Network not supported in simulation
void bThread::setConnection(int connection) {
    DBG1("Networking not implemented in simulation target");
    assert(false);
}

// Network not supported in simulation
void bThread::closeConnection() {
    DBG1("Networking not implemented in simulation target");
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
    DBG1("Networking not implemented in simulation target");
    assert(false);
}

// Network not supported in simulation
void bThread::connClose(bool client) {
    DBG1("Networking not implemented in simulation target");
    assert(false);
}

// ======-------------------------------------------------------------------------------
// DEBUG
// ======-------------------------------------------------------------------------------

void bThread::printDebug() {
    // Not implemented
} 

}
