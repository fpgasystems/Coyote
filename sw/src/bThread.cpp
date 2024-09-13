#include <iostream>
#include <fcntl.h>
#include <unistd.h>
#include <fstream>
#include <malloc.h>
#include <sys/mman.h>
#include <sys/ioctl.h>
#include <time.h> 
#include <sys/time.h>  
#include <chrono>
#include <iomanip>
#include <fcntl.h>
#include <syslog.h>
#include <random>

#include "bThread.hpp"

using namespace std::chrono;

namespace fpga {

// ======-------------------------------------------------------------------------------
// Notification handler
// ======-------------------------------------------------------------------------------

// Event-Handler function that is passed on to the event-handling thread. 
// efd - event file descriptor 
// terminate_efd - termination event file descriptor 
// uisr - pointer to the user interrupt service routine 
int eventHandler(int efd, int terminate_efd, void(*uisr)(int)) {
    # ifdef VERBOSE
        std::cout << "bThread: Called the eventHandler on event file descripter " << efd << " and termination event file descriptor " << terminate_efd << std::endl; 
    # endif

	struct epoll_event event, events[maxEvents]; // Single event and array of multiple events that should be observed 
	int epoll_fd = epoll_create1(0); // Create an instance of epoll and get the file descriptor back 
	int running = 1;

    // Check if the file descriptor for the event could be obtained 
	if (epoll_fd == -1) {
		throw new std::runtime_error("failed to create epoll file\n");
	}

    // Configure the event for efd
	event.events = EPOLLIN; // Watch out for read events
	event.data.fd = efd; // Configuration for efd 
    // Add the event to the epoll_fd that was created just before that 
	if (epoll_ctl(epoll_fd, EPOLL_CTL_ADD, efd, &event)) {
		throw new std::runtime_error("failed to add event to epoll");
	}

    // Configure the event for terminate_efd (same procedure as before, just different file descriptor)
	event.events = EPOLLIN;
	event.data.fd = terminate_efd;
	if (epoll_ctl(epoll_fd, EPOLL_CTL_ADD, efd, &event)) {
		throw new std::runtime_error("failed to add event to epoll");
	}

    // Event Loop: Continues processing while the thread is running 
	while (running) {
        // Wait indefinitely for the specified max number of events 
		int event_count = epoll_wait(epoll_fd, events, maxEvents, -1);
        // Variable to store the value read from the event file descriptor 
		eventfd_t val;
		for (int i = 0; i < event_count; i++) {
            // Check all events: If event is a efd, read it and forward it to user defined interrupt service routine for further handling 
			if (events[i].data.fd == efd) {
				eventfd_read(efd, &val);
                # ifdef VERBOSE
                    std::cout << "cThread: Caught an event which is" << efd << std::endl; 
                # endif
				uisr(val);
			}

            // If event is a terminate_efd, terminate the event thread 
			else if (events[i].data.fd == terminate_efd) {
                # ifdef VERBOSE
                    std::cout << "cThread: Caught a termination event which is" << terminate_efd << std::endl; 
                # endif
				running = 0;
			}
		}
	}

    // Check if the file could successfully be closed 
	if (close(epoll_fd))  {
		DBG3("Failed to close epoll file!");
	}

	return 0;
}

// ======-------------------------------------------------------------------------------
// bThread management
// ======-------------------------------------------------------------------------------

static unsigned seed = std::chrono::system_clock::now().time_since_epoch().count();

/**
 * @brief Construct a new bThread
 * 
 * @param vfid - vFPGA id
 * @param pid - host process id - vfid and pid together form a QPN for the RDMA connection controlled by this thread 
 *
 * Constructor that sets variables for vfid, cscheduler and lastly the plock (enum open_or_create and a generated name) 
 */
bThread::bThread(int32_t vfid, pid_t hpid, uint32_t dev, cSched *csched, void (*uisr)(int)) : vfid(vfid), csched(csched),
		plock(open_or_create, ("vpga_mtx_user_" + std::to_string(vfid)).c_str())
{
	DBG3("bThread:  opening vFPGA-" << vfid << ", hpid " << hpid);

    # ifdef VERBOSE
        std::cout << "bThread: Called the constructor for vfid " << vfid << ", hpid " << hpid << ", dev " << dev << std::endl; 
    # endif
    
	// Opens a device file path for READ and WRITE (with SYNC demands) and checks if that worked 
	std::string region = "/dev/fpga_" + std::to_string(dev) + "_v" + std::to_string(vfid); // Creates the name as string with the device-number and the vFGPA-ID 
	fd = open(region.c_str(), O_RDWR | O_SYNC); 
	if(fd == -1)
		throw std::runtime_error("bThread could not be obtained, vfid: " + to_string(vfid));

    # ifdef VERBOSE
        std::cout << "bThread: Called the constructor and opened up the device file path " << region << std::endl; 
    # endif

	// Registration
	uint64_t tmp[maxUserCopyVals]; // Array with 64-Bit-ints for copies of user variables 
    tmp[0] = hpid; // Store the host process ID in the first field of the array 
	
	// Register host pid with the device (ioctl being a driver call to do this)
	if(ioctl(fd, IOCTL_REGISTER_PID, &tmp))
		throw std::runtime_error("ioctl_register_pid() failed");

	DBG2("bThread:  ctor, ctid: " << tmp[1] << ", vfid: " << vfid <<  ", hpid: " << hpid);
	ctid = tmp[1];  // Store ctid in the tmp-register at the next position 

	// Cnfg - check if the device configuration can be read via ioctl 
	if(ioctl(fd, IOCTL_READ_CNFG, &tmp)) 
		throw std::runtime_error("ioctl_read_cnfg() failed");

    // Parse the FPGA configuration with the fCnfg-parsing function. tmp has been previously filled from the ioctl read-access. 
    # ifdef VERBOSE
        std::cout << "bThread: Parsed the configuration into register space." << std::endl; 
    # endif
	fcnfg.parseCnfg(tmp[0]);

    // Events - check if there's a pointer provided for user-defined interrupt service routine. Only then execute the following code block. 
    if (uisr) {
		tmp[0] = ctid; // Store the child thread ID in the temp-array 

        # ifdef VERBOSE
            std::cout << "bThread: user interrupt service routine is provided, store the ctid " << ctid << " and try to create efd and terminate_efd." << std::endl; 
        # endif

        // Try to create a new event file-descriptor initialized to 0 with standard flags 
		efd = eventfd(0, 0);
        // Check if the creation worked 
		if (efd == -1)
			throw std::runtime_error("bThread could not create eventfd");

        // Same procedure as before, but this time specifically for termination signals 
		terminate_efd = eventfd(0, 0);
		if (terminate_efd == -1)
			throw std::runtime_error("bThread could not create eventfd");
		
        // Store the event file descriptor in the temp-array for later usage 
		tmp[1] = efd;
		
        // Create the event handling thread with the handler-function, the event file descriptors and the interrupt service routine 
        # ifdef VERBOSE
            std::cout << "bThread: Create the event-handling thread with efd " << efd << " and terminate_efd " << terminate_efd << std::endl; 
        # endif
		event_thread = std::thread(eventHandler, efd, terminate_efd, uisr);

        // Registers the event file descriptor with the device via a ioctl-call. Throws error if that didn't work for some reason. 
		if (ioctl(fd, IOCTL_REGISTER_EVENTFD, &tmp))
			throw std::runtime_error("ioctl_eventfd_register() failed");
	}

    // Generate a new qpair for this thread 
    # ifdef VERBOSE
        std::cout << "bThread: Create a new qpair." << std::endl; 
    # endif
    qpair = std::make_unique<ibvQp>();

    // Check if RDMA-capability has been enabled in the settings (which have been read previously)
    if(fcnfg.en_rdma) {
        // Random number generators 
        std::default_random_engine rand_gen(seed);
        std::uniform_int_distribution<int> distr(0, std::numeric_limits<std::uint32_t>::max());

        // Read the IP-address via a ioctl-system call and store it in tmp 
        if (ioctl(fd, IOCTL_GET_IP_ADDRESS, &tmp))
			throw std::runtime_error("ioctl_get_ip_address() failed");

        // Assign the IP-address to the new qpair 
        uint32_t ibv_ip_addr = (uint32_t) tmp[0];// convert(tmp[0]);
        qpair->local.ip_addr = ibv_ip_addr;
        qpair->local.uintToGid(0, ibv_ip_addr);
        qpair->local.uintToGid(8, ibv_ip_addr);
        qpair->local.uintToGid(16, ibv_ip_addr);
        qpair->local.uintToGid(24, ibv_ip_addr);

        // qpn and psn
        qpair->local.qpn = ((vfid & nRegMask) << pidBits) || (ctid & pidMask); // QPN is concatinated from vfid and ctid 
        if(qpair->local.qpn == -1) 
            throw std::runtime_error("Coyote PID incorrect, vfid: " + std::to_string(vfid));
        qpair->local.psn = distr(rand_gen) & 0xFFFFFF; // Generate a random PSN to start with on the local side 
        qpair->local.rkey = 0; // Local rkey is hard-coded to 0 

        # ifdef VERBOSE
            std::cout << "bThread: RDMA is enabled, created the local QP with QPN " << qpair->local.qpn << ", local PSN " << qpair->local.psn << ", and local rkey " << qpair->local.rkey << "." << std::endl; 
        # endif
    }

	// Mmap - map the FPGA-memory 
	mmapFpga();

	// Clear
	clearCompleted();

    DBG3("bThread:  ctor finished");
}

/**
 * @brief Destroy the bThread
 * 
 */
bThread::~bThread() {
	DBG2("bThread:   dtor, ctid: " << ctid << ", vfid: " << vfid << ", hpid: " << hpid);

    # ifdef VERBOSE
        std::cout << "bThread: Called the destructor." << std::endl; 
    # endif
	
	uint64_t tmp[maxUserCopyVals];
    tmp[0] = ctid;

	// Memory: Free the memor and clear the mapped pages 
	for(auto& it: mapped_pages) {
		freeMem(it.first);
	}
	mapped_pages.clear();

    // Unmap the FPGA from the memory space 
	munmapFpga();

    // Unregister the PID as stored in the tmp-array 
	ioctl(fd, IOCTL_UNREGISTER_PID, &tmp);

    // If the event file descriptor exists, take care of destruction of the event-infrastructure 
    if (efd != -1) {
        // Unregister the event-file descriptor 
		ioctl(fd, IOCTL_UNREGISTER_EVENTFD, &tmp);

		/* Terminate the eventfd thread */
		eventfd_write(terminate_efd, 1);

		/* Wait for termination */
		event_thread.join();

		/* Close file descriptors */
		close(efd);
		close(terminate_efd);
	}

	named_mutex::remove(("vpga_mtx_user_" + std::to_string(vfid)).c_str());

	close(fd);
}

/**
 * @brief MMap vFPGA control plane
 * 
 */
void bThread::mmapFpga() {
    # ifdef VERBOSE
        std::cout << "bThread: Called mmapFpga to map vFPGA control plane." << std::endl; 
    # endif

	// Config 
#ifdef EN_AVX
	if(fcnfg.en_avx) {
		cnfg_reg_avx = (__m256i*) mmap(NULL, cnfgAvxRegionSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, mmapCnfgAvx);
		if(cnfg_reg_avx == MAP_FAILED)
		 	throw std::runtime_error("cnfg_reg_avx mmap failed");

		DBG3("bThread:  mapped cnfg_reg_avx at: " << std::hex << reinterpret_cast<uint64_t>(cnfg_reg_avx) << std::dec);
	} else {
#endif
        // Map the configuration register space in memory
		cnfg_reg = (uint64_t*) mmap(NULL, cnfgRegionSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, mmapCnfg);
		if(cnfg_reg == MAP_FAILED)
			throw std::runtime_error("cnfg_reg mmap failed");
		
		DBG3("bThread:  mapped cnfg_reg at: " << std::hex << reinterpret_cast<uint64_t>(cnfg_reg) << std::dec);
#ifdef EN_AVX
	}
#endif

	// Control - map the control register space in memory 
	ctrl_reg = (uint64_t*) mmap(NULL, ctrlRegionSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, mmapCtrl);
	if(ctrl_reg == MAP_FAILED) 
		throw std::runtime_error("ctrl_reg mmap failed");
	
	DBG3("bThread:  mapped ctrl_reg at: " << std::hex << reinterpret_cast<uint64_t>(ctrl_reg) << std::dec);

	// Writeback
	if(fcnfg.en_wb) {
        // Map writeback-region in memory 
		wback = (uint32_t*) mmap(NULL, wbackRegionSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, mmapWb);
		if(wback == MAP_FAILED) 
			throw std::runtime_error("wback mmap failed");

		DBG3("bThread:  mapped writeback regions at: " << std::hex << reinterpret_cast<uint64_t>(wback) << std::dec);
	}
}

/**
 * @brief Munmap vFPGA control plane
 * 
 */
void bThread::munmapFpga() {
	// Same as before, but this time unmap all the different memory spaces
    # ifdef VERBOSE
        std::cout << "bThread: Called munmapFpga to map vFPGA control plane." << std::endl; 
    # endif

	// Config
#ifdef EN_AVX
	if(fcnfg.en_avx) {
		if(munmap((void*)cnfg_reg_avx, cnfgAvxRegionSize) != 0) 
			throw std::runtime_error("cnfg_reg_avx munmap failed");
	} else {
#endif
		if(munmap((void*)cnfg_reg, cnfgRegionSize) != 0) 
			throw std::runtime_error("cnfg_reg munmap failed");
#ifdef EN_AVX
	}
#endif

	// Control
	if(munmap((void*)ctrl_reg, ctrlRegionSize) != 0)
		throw std::runtime_error("ctrl_reg munmap failed");

	// Writeback
	if(fcnfg.en_wb) {
		if(munmap((void*)wback, wbackRegionSize) != 0)
			throw std::runtime_error("wback munmap failed");
	}

#ifdef EN_AVX
	cnfg_reg_avx = 0;
#endif
	cnfg_reg = 0;
	ctrl_reg = 0;
	wback = 0;
}

// ======-------------------------------------------------------------------------------
// Schedule threads
// ======-------------------------------------------------------------------------------

/**
 * @brief Obtain vFPGA lock (if scheduler is not present obtain system lock)
 * 
 * @param oid - operator id
 * @param priority - priority
 */
void bThread::pLock(int32_t oid, uint32_t priority) 
{
    # ifdef VERBOSE
        std::cout << "bThread: Close the pLock." << std::endl; 
    # endif
    if(csched != nullptr) {
        csched->pLock(ctid, oid, priority); 
    } else {
        plock.lock();
    }
}

void bThread::pUnlock() 
{
    # ifdef VERBOSE
        std::cout << "bThread: Open the pLock." << std::endl; 
    # endif
    if(csched != nullptr) {
        csched->pUnlock(ctid); 
    } else {
        plock.unlock();
    }
}

// ======-------------------------------------------------------------------------------
// Memory management
// ======-------------------------------------------------------------------------------

/**
 * @brief Explicit TLB mapping 
 * 
 * @param vaddr - user space address
 * @param len - length 
 *
 * Manual memory mapping for user-defined regions in the memory space
 */
void bThread::userMap(void *vaddr, uint32_t len, bool remote) {

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

/**
 * @brief TLB unmap
 * 
 * @param vaddr - user space address
 *
 * Opposite of previous function: Unmap from memory 
 */
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

/**
 * @brief Memory allocation
 * 
 * @param cs_alloc - Coyote allocation struct, defined in cDefs.hpp. Has information about size, RDMA-connection, device-number, file-descriptor and the actual memory-pointer
 * @return void* - pointer to the allocated memory
 *
 */
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

/**
 * @brief Memory deallocation
 * 
 * @param vaddr - pointer to the allocated memory
 *
 * Opposite of the function above - deallocate memory that is no longer required 
 */
void bThread::freeMem(void* vaddr) {

    # ifdef VERBOSE
        std::cout << "bThread: Free memory." << std::endl; 
    # endif

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

// Send commands to the device 
void bThread::postCmd(uint64_t offs_3, uint64_t offs_2, uint64_t offs_1, uint64_t offs_0) {
    # ifdef VERBOSE
        std::cout << "bThread: Post a command to the FPGA-device." << std::endl; 
        std::cout << " - bThread - offs3: " << offs_3 << std::endl; 
        std::cout << " - bThread - offs2: " << offs_2 << std::endl; 
        std::cout << " - bThread - offs1: " << offs_1 << std::endl; 
        std::cout << " - bThread - offs0: " << offs_0 << std::endl; 
    # endif

    //
    // Check outstanding commands
    //
    while (cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr)) {

        // Anyways: Extract the command count, for both AVX and non-AVX-implementations
#ifdef EN_AVX
        cmd_cnt = fcnfg.en_avx ? LOW_32(_mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::CTRL_REG)], 0x0)) :
                                    cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::CTRL_REG)];
#else
        cmd_cnt = cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::CTRL_REG)];
        # ifdef VERBOSE
            std::cout << "bThread: Current command count: " << cmd_cnt << std::endl; 
        # endif
#endif
        if (cmd_cnt > (cmd_fifo_depth - cmd_fifo_thr)) 
            std::this_thread::sleep_for(std::chrono::nanoseconds(sleepTime));
    }

    //
    // Send commands - use the input offsets to set control registers for writing the desired command 
    //
#ifdef EN_AVX
    if(fcnfg.en_avx) {
        // Fire AVX
        cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::CTRL_REG)] = 
            _mm256_set_epi64x(offs_3, offs_2, offs_1, offs_0);
    } else {
#endif
        // Fire legacy
        cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::VADDR_WR_REG)] = offs_3;
        cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::CTRL_REG_2)] = offs_2;
        cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::VADDR_RD_REG)] = offs_1;
        cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::CTRL_REG)] = offs_0;
#ifdef EN_AVX
    }
#endif

    // Inc
    cmd_cnt++;
}

/**
 * @brief Inovoke data transfers (local)    
 * 
 * @param coper - operation
 * @param sg_list - scatter/gather list
 * @param sg_flags - completion flags
 * @param n_st - number of sg entries
 */
void bThread::invoke(CoyoteOper coper, sgEntry *sg_list, sgFlags sg_flags, uint32_t n_sg) {
    # ifdef VERBOSE
        std::cout << "bThread: Call invoke for operation " << coper << " and the following number of sg-entries " << n_sg << std::endl; 
    # endif

    // First of all: Check whether the coyote operation can be executed given the system settings in the FPGA-configuration 
	if(isLocalSync(coper)) if(!fcnfg.en_mem) return;
    if(isRemoteRdma(coper)) if(!fcnfg.en_rdma) return;
    if(isRemoteTcp(coper)) if(!fcnfg.en_tcp) return;
	if(coper == CoyoteOper::NOOP) return;

    // Handle first case, when Coyote operation is a local sync operation 
    if(isLocalSync(coper)) { 
        //
        // Sync mem ops
        //

        uint64_t tmp[maxUserCopyVals];
        tmp[1] = ctid;

        if(coper == CoyoteOper::LOCAL_OFFLOAD) {
            // Offload: Iterate over entries of the scatter-gather-list and initiate the offload for every entry
            # ifdef VERBOSE
                std::cout << "bThread: Received a LOCAL_OFFLOAD operation." << std::endl; 
            # endif

            for(int i = 0; i < n_sg; i++) {
                tmp[0] = reinterpret_cast<uint64_t>(sg_list[i].sync.addr);
                if(ioctl(fd, IOCTL_OFFLOAD_REQ, &tmp))
		            throw std::runtime_error("ioctl_offload_req() failed");
            }  
        }
        else if (coper == CoyoteOper::LOCAL_SYNC) {
            // Sync: Iterate over entries of the scatter-gather-list and initiate the sync-operation for every entry
            # ifdef VERBOSE
                std::cout << "bThread: Received a LOCAL_SYNC operation." << std::endl; 
            # endif

            for(int i = 0; i < n_sg; i++) {
                tmp[0] = reinterpret_cast<uint64_t>(sg_list[i].sync.addr);
                if(ioctl(fd, IOCTL_SYNC_REQ, &tmp))
                    throw std::runtime_error("ioctl_sync_req() failed");
            }
        }
    } else { 
        //
        // Local and remote ops
        //

        // Arrays for src + dst address, src + dst ctrl for all entries of the scatter-gather-list 
        uint64_t addr_cmd_src[n_sg], addr_cmd_dst[n_sg];
        uint64_t ctrl_cmd_src[n_sg], ctrl_cmd_dst[n_sg];

        // Values for remote and local addr and ctrl 
        uint64_t addr_cmd_r, addr_cmd_l;
        uint64_t ctrl_cmd_r, ctrl_cmd_l;

        // Clear
        if(sg_flags.clr && fcnfg.en_wb) {
            for(int i = 0; i < nWbacks; i++) {
                wback[ctid + i*nCtidMax] = 0;
            }
        }

        // SG traverse - iterate over all entries of the scatter-gather list 
        for(int i = 0; i < n_sg; i++) {

            //
            // Construct the post cmd
            //
            if(isRemoteTcp(coper)) {
                // TCP - addr is 0, ctrl source is 0, ctrl destination is calculated from 
                ctrl_cmd_src[i] = 0;
                addr_cmd_src[i] = 0;
                ctrl_cmd_dst[i] = 
                    ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS) |
                    ((sg_list[i].tcp.stream & CTRL_STRM_MASK) << CTRL_STRM_OFFS) | 
                    ((sg_list[i].tcp.dest & CTRL_DEST_MASK) << CTRL_DEST_OFFS) |
                    ((i == (n_sg-1) ? ((sg_flags.last) ? CTRL_LAST : 0x0) : 0x0)) |
                    (CTRL_START) |
                    (static_cast<uint64_t>(sg_list[i].tcp.len) << CTRL_LEN_OFFS);

                addr_cmd_dst[i] = 0;

           } else if(isRemoteRdma(coper)) {
                // RDMA
                # ifdef VERBOSE
                    std::cout << "bThread: Invoked operation is remote RDMA." << std::endl; 
                # endif

                // If local and remote IP-address are the same, then this is a local transfer of data rather than a network operation 
                if(qpair->local.ip_addr == qpair->remote.ip_addr) {
                    # ifdef VERBOSE
                        std::cout << "bThread: RDMA remote and local node are identical." << std::endl; 
                    # endif
                    for(int i = 0; i < n_sg; i++) {
                        void *local_addr = (void*)((uint64_t)qpair->local.vaddr + sg_list[i].rdma.local_offs);
                        void *remote_addr = (void*)((uint64_t)qpair->remote.vaddr + sg_list[i].rdma.remote_offs);

                        // Copy data around - the actual, local data transfer via memcpy from source to destination address
                        memcpy(remote_addr, local_addr, sg_list[i].rdma.len);
                        continue;
                    }
                } else {
                    // If local and remote IP-address are different from each other, we need to create two commands, one for local (read / write) and one for remote (RDMA-network command)
                    # ifdef VERBOSE
                        std::cout << "bThread: RDMA remote and local node are not identical." << std::endl; 
                    # endif
                    
                    // Local - local stream is selected from the sg-list
                    ctrl_cmd_l =
                        // Cmd l
                        (((static_cast<uint64_t>(coper) - remoteOffsOps) & CTRL_OPCODE_MASK) << CTRL_OPCODE_OFFS) |
                        ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS) |
                        ((sg_list[i].rdma.local_dest & CTRL_DEST_MASK) << CTRL_DEST_OFFS) |
                        ((i == (n_sg-1) ? ((sg_flags.last) ? CTRL_LAST : 0x0) : 0x0)) |
                        ((sg_list[i].rdma.local_stream & CTRL_STRM_MASK) << CTRL_STRM_OFFS) | 
                        (sg_flags.clr ? CTRL_CLR_STAT : 0x0) | 
                        (static_cast<uint64_t>(sg_list[i].rdma.len) << CTRL_LEN_OFFS);
                    
                    # ifdef VERBOSE
                        std::cout << " - bThread: local contral command " << ctrl_cmd_l << std::endl; 
                    # endif
                    
                    // Local address is generated from the QP local address and the sg-list local offset
                    addr_cmd_l = static_cast<uint64_t>((uint64_t)qpair->local.vaddr + sg_list[i].rdma.local_offs);

                    # ifdef VERBOSE
                        std::cout << " - bThread: local command address " << addr_cmd_l << std::endl; 
                    # endif

                    // Remote - remote stream is always the RDMA-stream
                    ctrl_cmd_r =                    
                        // Cmd l
                        (((static_cast<uint64_t>(coper) - remoteOffsOps) & CTRL_OPCODE_MASK) << CTRL_OPCODE_OFFS) |
                        ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS) |
                        ((sg_list[i].rdma.remote_dest & CTRL_DEST_MASK) << CTRL_DEST_OFFS) |
                        ((i == (n_sg-1) ? ((sg_flags.last) ? CTRL_LAST : 0x0) : 0x0)) |
                        ((strmRdma & CTRL_STRM_MASK) << CTRL_STRM_OFFS) | 
                        (CTRL_START) |
                        (sg_flags.clr ? CTRL_CLR_STAT : 0x0) | 
                        (static_cast<uint64_t>(sg_list[i].rdma.len) << CTRL_LEN_OFFS);

                    # ifdef VERBOSE
                        std::cout << " - bThread: remote control command " << ctrl_cmd_r << std::endl; 
                    # endif

                    // Remote address is generated from the QP remote address and the sg-list remote offset 
                    addr_cmd_r = static_cast<uint64_t>((uint64_t)qpair->remote.vaddr + sg_list[i].rdma.remote_offs); 

                    # ifdef VERBOSE
                        std::cout << " - bThread: remote command address " << addr_cmd_r << std::endl; 
                    # endif 

                    // Order - based on the distinction between Read and Write, determine what is source and what is destination 
                    ctrl_cmd_src[i] = isRemoteRead(coper) ? ctrl_cmd_r : ctrl_cmd_l;
                    addr_cmd_src[i] = isRemoteRead(coper) ? addr_cmd_r : addr_cmd_l;
                    ctrl_cmd_dst[i] = isRemoteRead(coper) ? ctrl_cmd_l : ctrl_cmd_r;
                    addr_cmd_dst[i] = isRemoteRead(coper) ? addr_cmd_l : addr_cmd_r;
                }

            } else {
                // Third (remote) option (not quite clear what this means if it's not TCP or RDMA)

                # ifdef VERBOSE
                    std::cout << "bThread: Third remote option for a command." << std::endl; 
                # endif

                // Local
                ctrl_cmd_src[i] =
                    // RD
                    ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS) |
                    ((sg_list[i].local.src_dest & CTRL_DEST_MASK) << CTRL_DEST_OFFS) |
                    ((i == (n_sg-1) ? ((sg_flags.last) ? CTRL_LAST : 0x0) : 0x0)) |
                    ((sg_list[i].local.src_stream & CTRL_STRM_MASK) << CTRL_STRM_OFFS) | 
                    (isLocalRead(coper) ? CTRL_START : 0x0) | 
                    (sg_flags.clr ? CTRL_CLR_STAT : 0x0) | 
                    (static_cast<uint64_t>(sg_list[i].local.src_len) << CTRL_LEN_OFFS);

                addr_cmd_src[i] = reinterpret_cast<uint64_t>(sg_list[i].local.src_addr);

                ctrl_cmd_dst[i] =
                    // WR
                    ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS) |
                    ((sg_list[i].local.dst_dest & CTRL_DEST_MASK) << CTRL_DEST_OFFS) |
                    ((i == (n_sg-1) ? ((sg_flags.last) ? CTRL_LAST : 0x0) : 0x0)) |
                    ((sg_list[i].local.dst_stream & CTRL_STRM_MASK) << CTRL_STRM_OFFS) | 
                    (isLocalWrite(coper) ? CTRL_START : 0x0) | 
                    (sg_flags.clr ? CTRL_CLR_STAT : 0x0) | 
                    (static_cast<uint64_t>(sg_list[i].local.dst_len) << CTRL_LEN_OFFS);

                addr_cmd_dst[i] = reinterpret_cast<uint64_t>(sg_list[i].local.dst_addr);
            }

            // Use the post command hook to post the previously generated command (probably to the driver)
            postCmd(addr_cmd_dst[i], ctrl_cmd_dst[i], addr_cmd_src[i], ctrl_cmd_src[i]);
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

/**
 * @brief Check number of completed operations
 * 
 * @param coper - Coyote operation struct
 * @return uint32_t - number of completed operations
 */
uint32_t bThread::checkCompleted(CoyoteOper coper) {
    // Based on the type of operation, check completion via a read access to the configuration registers 

    # ifdef VERBOSE
        std::cout << "bThread: Check for completion of a coper " << coper << std::endl; 
    # endif

	if(isCompletedLocalRead(coper)) {
		if(fcnfg.en_wb) {
			return wback[ctid + rdWback*nCtidMax];
		} else {
#ifdef EN_AVX
			if(fcnfg.en_avx)
                // _mm256_extract_epi32 is used to extract a 32-Bit Integer from a full 256-Bit Vector (parameter a) at a specified position (parameter b)
				return _mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::STAT_DMA_REG) + ctid], 0);
			else 
#endif
				return (LOW_32(cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::STAT_DMA_REG) + ctid]));
		}
	}
    else if(isCompletedLocalWrite(coper)) {
		if(fcnfg.en_wb) {
            return wback[ctid + wrWback*nCtidMax];
		} else {
#ifdef EN_AVX
			if(fcnfg.en_avx) 
				return _mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::STAT_DMA_REG) + ctid], 1);
			else
#endif
				return (HIGH_32(cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::STAT_DMA_REG) + ctid]));
		}
	} else if(isRemoteRead(coper)) {
		if(fcnfg.en_wb) {
			return wback[ctid + rdRdmaWback*nCtidMax];
		} else {
#ifdef EN_AVX
			if(fcnfg.en_avx) 
				return _mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::STAT_DMA_REG) + ctid], 2);
			else 
#endif
				return (LOW_32(cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::STAT_RDMA_REG) + ctid]));
		}
	} else if(isRemoteWriteOrSend(coper)) {
        if(fcnfg.en_wb) {
            return wback[ctid + wrRdmaWback*nCtidMax];
        } else {
#ifdef EN_AVX
            if(fcnfg.en_avx) 
                return _mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::STAT_DMA_REG) + ctid], 3);
            else
#endif
                return (HIGH_32(cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::STAT_RDMA_REG) + ctid]));  
        }
    } else {
        return 0;
    }
}

/**
 * @brief Clear completion counters - analog to previous function, access the same registers and reset them (write-access)
 * 
 */
void bThread::clearCompleted() {
    # ifdef VERBOSE
        std::cout << "bThread: Called clearCompleted()" << std::endl; 
    # endif
    if(fcnfg.en_wb) {
        for(int i = 0; i < nWbacks; i++) {
            wback[ctid + i*nCtidMax] = 0;
        }
    }

#ifdef EN_AVX
	if(fcnfg.en_avx) {
		cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::CTRL_REG)] = _mm256_set_epi64x(0, CTRL_CLR_STAT | ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS), 0, CTRL_CLR_STAT | ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS));
    } else 
#endif
    {
		cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::CTRL_REG_2)] = CTRL_CLR_STAT | ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS);
        cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::CTRL_REG)] = CTRL_CLR_STAT | ((ctid & CTRL_PID_MASK) << CTRL_PID_OFFS);
    }
}

// ======-------------------------------------------------------------------------------
// Network management
// ======-------------------------------------------------------------------------------

/**
 * @brief ARP lookup request - doesn't deliver the MAC-address back for some reason, just a bool if task has been triggered 
 * 
 * @param ip_addr - target IP address
 */
bool bThread::doArpLookup(uint32_t ip_addr) {
    # ifdef VERBOSE
        std::cout << "bThread: Called doArpLookup for IP-address " << ip_addr << std::endl; 
    # endif

#ifdef EN_AVX
    // General structure: Check a config-register. Based on the result, either send out FALSE or store IP-address in another config-register
	if(fcnfg.en_avx) {
        if(_mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::NET_ARP_REG)], 0))
            cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::NET_ARP_REG)] = _mm256_set_epi64x(0, 0, 0, ip_addr);
        else
            return false;
    } else {
#endif
        if((LOW_32(cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::NET_ARP_REG)])))
            cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::NET_ARP_REG)] = ip_addr;
        else
            return false;
    }

	usleep(arpSleepTime);

    return true;
}

/**
 * @brief Write queue pair context
 * 
 * @param qp - queue pair struct
 */
bool bThread::writeQpContext(uint32_t port) {
    // Basic idea: Get information from the previously created qp-struct and write it to configuration memory 
    uint64_t offs[3];
    if(fcnfg.en_rdma) {
        // Write QP context - QPN, rkey, local and remote PSN, vaddr
        offs[0] = ((static_cast<uint64_t>(qpair->local.qpn) & 0xffffff) << qpContextQpnOffs) |
                  ((static_cast<uint64_t>(qpair->remote.rkey) & 0xffffffff) << qpContextRkeyOffs) ;

        offs[1] = ((static_cast<uint64_t>(qpair->local.psn) & 0xffffff) << qpContextLpsnOffs) | 
                ((static_cast<uint64_t>(qpair->remote.psn) & 0xffffff) << qpContextRpsnOffs);

        offs[2] = ((static_cast<uint64_t>((uint64_t)qpair->remote.vaddr) & 0xffffffffffff) << qpContextVaddrOffs);

        # ifdef VERBOSE
            std::cout << "bThread: Called writeQpContext on a RDMA-enabled design." << std::endl;
            std::cout << " - bThread - offs[0] " << offs[0] << std::endl; 
            std::cout << " - bThread - offs[1] " << offs[1] << std::endl; 
            std::cout << " - bThread - offs[1] " << offs[2] << std::endl;  
        # endif
    	
        // Write this information obtained from the QP-struct into configuration memory / registers 
#ifdef EN_AVX
        if(fcnfg.en_avx) {
            if(_mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::RDMA_CTX_REG)], 0))
                cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::RDMA_CTX_REG)] = _mm256_set_epi64x(0, offs[2], offs[1], offs[0]);
            else
                return false;
        } else
#endif
        {
            if((LOW_32(cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_CTX_REG_2)]))) {
                cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_CTX_REG_0)] = offs[0];
                cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_CTX_REG_1)] = offs[1];
                cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_CTX_REG_2)] = offs[2];
            } else
                return false;
        }

        // Write Conn context - port (given as function argument), local and remote QPN, GID etc. to the local memory 
        offs[0] = ((static_cast<uint64_t>(port) & 0xffff) << connContextPortOffs) | 
                ((static_cast<uint64_t>(qpair->remote.qpn) & 0xffffff) << connContextRqpnOffs) | 
                ((static_cast<uint64_t>(qpair->local.qpn) & 0xffff) << connContextLqpnOffs);

        offs[1] = (htols(static_cast<uint64_t>(qpair->remote.gidToUint(8)) & 0xffffffff) << 32) |
                    (htols(static_cast<uint64_t>(qpair->remote.gidToUint(0)) & 0xffffffff) << 0);

        offs[2] = (htols(static_cast<uint64_t>(qpair->remote.gidToUint(24)) & 0xffffffff) << 32) | 
                    (htols(static_cast<uint64_t>(qpair->remote.gidToUint(16)) & 0xffffffff) << 0);

        // Write this information to register space 
#ifdef EN_AVX
        if(fcnfg.en_avx) {
            if(_mm256_extract_epi32(cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::RDMA_CONN_REG)], 0))
                cnfg_reg_avx[static_cast<uint32_t>(CnfgAvxRegs::RDMA_CONN_REG)] = _mm256_set_epi64x(0, offs[2], offs[1], offs[0]);
            else
                return false;
        } else
#endif
        {
            if((LOW_32(cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_CONN_REG_2)]))) {
                cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_CONN_REG_0)] = offs[0];
                cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_CONN_REG_1)] = offs[1];
                cnfg_reg[static_cast<uint32_t>(CnfgLegRegs::RDMA_CONN_REG_2)] = offs[2];
            } else
                return false;
        }

        return true;
    }

    return false;
}

/**
 * @brief Set connection
 */
void bThread::setConnection(int connection) {
    # ifdef VERBOSE
        std::cout << "bThread: Called to set a connection " << connection << std::endl; 
    # endif
    this->connection = connection;
    is_connected = true;
}

/**
 * @brief Close connection
*/
void bThread::closeConnection() {
    # ifdef VERBOSE
        std::cout << "bThread: Called to close a connection." << std::endl; 
    # endif
    if(isConnected()) {
        close(connection);
        is_connected = false;
    }
}

/**
 * Sync with remote
 */
uint32_t bThread::readAck() {
    # ifdef VERBOSE
        std::cout << "bThread: Called to read an ACK" << std::endl; 
    # endif

    uint32_t ack;
   
    if (::read(connection, &ack, sizeof(uint32_t)) != sizeof(uint32_t)) {
        ::close(connection);
        throw std::runtime_error("Could not read ack\n");
    }

    return ack;
}

/**
 * Sync with remote
 * @param: ack - acknowledge message
 */
void bThread::sendAck(uint32_t ack) {
    # ifdef VERBOSE
        std::cout << "bThread: Called to send an ACK" << std::endl; 
    # endif

    if(::write(connection, &ack, sizeof(uint32_t)) != sizeof(uint32_t))  {
        ::close(connection);
        throw std::runtime_error("Could not send ack\n");
    }
}

/**
 * Wait on close remote
 */
void bThread::closeAck() {
    # ifdef VERBOSE
        std::cout << "bThread: Called to receive a closeAck." << std::endl; 
    # endif

    uint32_t ack;
    
    if (::read(connection, &ack, sizeof(uint32_t)) == 0) {
        ::close(connection);
    }
}

/**
 * Sync with remote - handshaking based on the ACK-functions as defined above 
 */
void bThread::connSync(bool client) {
    # ifdef VERBOSE
        std::cout << "bThread: Called connSync for handshaking." << std::endl; 
    # endif

    if(client) {
        sendAck(0);
        readAck();
    } else {
        readAck();
        sendAck(0);
    }
}

/**
 * Close connections
 */
void bThread::connClose(bool client) {
    # ifdef VERBOSE
        std::cout << "bThread: Called to close a connection." << std::endl; 
    # endif
    if(client) {
        sendAck(1);
        closeAck();
    } else {
        readAck();
        closeConnection();
    }
}

// ======-------------------------------------------------------------------------------
// DEBUG
// ======-------------------------------------------------------------------------------

/**
 * Debug
 * 
 */
void bThread::printDebug()
{
    // Prints data from the config-registers
	std::cout << "-- STATISTICS - ID: " << getVfid() << std::endl;
	std::cout << "-----------------------------------------------" << std::endl;
#ifdef EN_AVX
	if(fcnfg.en_avx) {
		std::cout << std::setw(35) << "Sent local reads: \t" <<  _mm256_extract_epi64(cnfg_reg_avx[static_cast<uint64_t>(CnfgAvxRegs::STAT_REG_0)], 0x0) << std::endl;
        std::cout << std::setw(35) << "Sent local writes: \t" <<  _mm256_extract_epi64(cnfg_reg_avx[static_cast<uint64_t>(CnfgAvxRegs::STAT_REG_0)], 0x1) << std::endl;
        std::cout << std::setw(35) << "Sent remote reads: \t" <<  _mm256_extract_epi64(cnfg_reg_avx[static_cast<uint64_t>(CnfgAvxRegs::STAT_REG_0)], 0x2) << std::endl;
        std::cout << std::setw(35) << "Sent remote writes: \t" <<  _mm256_extract_epi64(cnfg_reg_avx[static_cast<uint64_t>(CnfgAvxRegs::STAT_REG_0)], 0x3) << std::endl;
        
        std::cout << std::setw(35) << "Invalidations received: \t" <<  _mm256_extract_epi64(cnfg_reg_avx[static_cast<uint64_t>(CnfgAvxRegs::STAT_REG_1)], 0x0) << std::endl;
        std::cout << std::setw(35) << "Page faults received: \t" <<  _mm256_extract_epi64(cnfg_reg_avx[static_cast<uint64_t>(CnfgAvxRegs::STAT_REG_1)], 0x1) << std::endl;
        std::cout << std::setw(35) << "Notifications received: \t" <<  _mm256_extract_epi64(cnfg_reg_avx[static_cast<uint64_t>(CnfgAvxRegs::STAT_REG_1)], 0x2) << std::endl;
	} else {
#endif
		std::cout << std::setw(35) << "Sent local reads: \t" <<  cnfg_reg[static_cast<uint64_t>(CnfgLegRegs::STAT_REG_0)] << std::endl;
        std::cout << std::setw(35) << "Sent local writes: \t" <<  cnfg_reg[static_cast<uint64_t>(CnfgLegRegs::STAT_REG_1)] << std::endl;
        std::cout << std::setw(35) << "Sent remote reads: \t" <<  cnfg_reg[static_cast<uint64_t>(CnfgLegRegs::STAT_REG_2)] << std::endl;
        std::cout << std::setw(35) << "Sent remote writes: \t" <<  cnfg_reg[static_cast<uint64_t>(CnfgLegRegs::STAT_REG_3)] << std::endl;

        std::cout << std::setw(35) << "Invalidations received: \t" <<  cnfg_reg[static_cast<uint64_t>(CnfgLegRegs::STAT_REG_4)] << std::endl;
        std::cout << std::setw(35) << "Page faults received: \t" <<  cnfg_reg[static_cast<uint64_t>(CnfgLegRegs::STAT_REG_5)] << std::endl;
        std::cout << std::setw(35) << "Notifications received: \t" <<  cnfg_reg[static_cast<uint64_t>(CnfgLegRegs::STAT_REG_6)] << std::endl;	
#ifdef EN_AVX
	}
#endif
	std::cout << std::endl;
} 

}
