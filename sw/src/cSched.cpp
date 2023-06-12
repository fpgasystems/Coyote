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

#include "cSched.hpp"

using namespace std::chrono;

namespace fpga
{

	// ======-------------------------------------------------------------------------------
	// cSched management
	// ======-------------------------------------------------------------------------------

	/**
	 * @brief Construct a new cSched, bitstream handler
	 *
	 * @param vfid - vFPGA id
	 */
	cSched::cSched(int32_t vfid, bool priority, bool reorder)
		: vfid(vfid), priority(priority), reorder(reorder),
		  mlock(open_or_create, "vpga_mtx_mem_" + vfid),
		  plock(open_or_create, "vpga_mtx_user_" + vfid),
		  request_queue(taskCmprSched(priority, reorder))
	{
		DBG3("(DBG!) Acquiring cSched: " << vfid);
		// Open
		std::string region = "/dev/fpga" + std::to_string(vfid);
		fd = open(region.c_str(), O_RDWR | O_SYNC);
		if (fd == -1)
			throw std::runtime_error("cSched could not be obtained, vfid: " + to_string(vfid));

		// Cnfg
		uint64_t tmp[2];

		if (ioctl(fd, IOCTL_READ_CNFG, &tmp))
			throw std::runtime_error("ioctl_read_cnfg() failed, vfid: " + to_string(vfid));

		fcnfg.parseCnfg(tmp[0]);
	}

	/**
	 * @brief Destructor cSched
	 *
	 */
	cSched::~cSched()
	{
		DBG3("cSched:  dtor called, vfid: " << vfid);
		run = false;

		DBG3("cSched:  joining");
		scheduler_thread.join();

		// Mapped
		for (auto &it : bstreams)
		{
			removeBitstream(it.first);
		}

		for (auto &it : mapped_pages)
		{
			freeMem(it.first);
		}

		named_mutex::remove("vfpga_mtx_mem_" + vfid);

		close(fd);
	}

	/**
	 * @brief Run the thread
	 *
	 */
	void cSched::run_sched()
	{
        unique_lock<mutex> lck_q(mtx_queue);

		// Thread
		DBG3("cSched:  initial lock");

		scheduler_thread = thread(&cSched::processRequests, this);
		DBG3("cSched:  thread started, vfid: " << vfid);

		cv_queue.wait(lck_q);
		DBG3("cSched:  ctor finished, vfid: " << vfid);
	}

	// ======-------------------------------------------------------------------------------
	// (Thread) Process requests
	// ======-------------------------------------------------------------------------------
	void cSched::processRequests()
	{
		unique_lock<mutex> lck_q(mtx_queue);
		unique_lock<mutex> lck_r(mtx_rcnfg);
		run = true;
		bool recIssued = false;
		int32_t curr_oid = -1;
		cv_queue.notify_one();
		lck_q.unlock();
		lck_r.unlock();
		;

		while (run || !request_queue.empty())
		{
			lck_q.lock();
			if (!request_queue.empty())
			{
				// Grab next reconfig request
				auto curr_req = std::move(const_cast<std::unique_ptr<cLoad> &>(request_queue.top()));
				request_queue.pop();
				lck_q.unlock();

				// Obtain vFPGA
				plock.lock();

				// Check whether reconfiguration is needed
				if (isReconfigurable())
				{
					if (curr_oid != curr_req->oid)
					{
						reconfigure(curr_req->oid);
						recIssued = true;
						curr_oid = curr_req->oid;
					}
					else
					{
						recIssued = false;
					}
				}

				// Notify
				lck_r.lock();
				curr_cpid = curr_req->cpid;
				curr_run = true;
				lck_r.unlock();
				cv_rcnfg.notify_all();

				// Wait for task completion
				unique_lock<mutex> lck_c(mtx_cmplt);
				if (cv_cmplt.wait_for(lck_c, cmplTimeout, [=]
									  { return curr_run == false; }))
				{
					syslog(LOG_NOTICE, "Task completed, %s, cpid %d, oid %d, priority %d\n",
						   (recIssued ? "operator loaded, " : "operator present, "), curr_req->cpid, curr_req->oid, curr_req->priority);
				}
				else
				{
					syslog(LOG_NOTICE, "Task failed, cpid %d, oid %d, priority %d\n",
						   curr_req->cpid, curr_req->oid, curr_req->priority);
				}

				plock.unlock();
			}
			else
			{
				lck_q.unlock();
			}

			nanosleep(&PAUSE, NULL);
		}
	}

	void cSched::pLock(int32_t cpid, int32_t oid, uint32_t priority)
	{
		unique_lock<std::mutex> lck_q(mtx_queue);
		request_queue.emplace(std::unique_ptr<cLoad>(new cLoad{cpid, oid, priority}));
		lck_q.unlock();

		unique_lock<std::mutex> lck_r(mtx_rcnfg);
		cv_rcnfg.wait(lck_r, [=]
					  { return ((curr_run == true) && (curr_cpid == cpid)); });
	}

	void cSched::pUnlock(int32_t cpid)
	{
		unique_lock<std::mutex> lck_c(mtx_cmplt);
		if (curr_cpid == cpid)
		{
			curr_run = false;
			cv_cmplt.notify_one();
		}
	}

	// ======-------------------------------------------------------------------------------
	// Memory management
	// ======-------------------------------------------------------------------------------

	/**
	 * @brief Bitstream memory allocation
	 *
	 * @param cs_alloc - allocatin config
	 * @return void* - pointer to allocated mem
	 */
	void *cSched::getMem(const csAlloc &cs_alloc)
	{
		void *mem = nullptr;
		void *memNonAligned = nullptr;
		uint64_t tmp[2];
		uint32_t size;

		if (cs_alloc.n_pages > 0)
		{
			tmp[0] = static_cast<uint64_t>(cs_alloc.n_pages);

			switch (cs_alloc.alloc)
			{
			case CoyoteAlloc::RCNFG_2M: // m lock

				mLock();

				if (ioctl(fd, IOCTL_ALLOC_HOST_PR_MEM, &tmp))
				{
					mUnlock();
					throw std::runtime_error("ioctl_alloc_host_pr_mem mapping failed");
				}

				memNonAligned = mmap(NULL, (cs_alloc.n_pages + 1) * hugePageSize, PROT_READ | PROT_WRITE, MAP_SHARED, fd, mmapPr);
				if (memNonAligned == MAP_FAILED)
				{
					mUnlock();
					throw std::runtime_error("get_pr_mem mmap failed");
				}

				mUnlock();

				mem = (void *)((((reinterpret_cast<uint64_t>(memNonAligned) + hugePageSize - 1) >> hugePageShift)) << hugePageShift);

				break;

			default:
				throw std::runtime_error("unauthorized memory allocation, vfid: " + to_string(vfid));
			}

			mapped_pages.emplace(mem, std::make_pair(cs_alloc, memNonAligned));
			DBG3("Mapped mem at: " << std::hex << reinterpret_cast<uint64_t>(mem) << std::dec);
		}

		return mem;
	}

	/**
	 * @brief Bitstream memory deallocation
	 *
	 * @param vaddr - mapped al
	 */
	void cSched::freeMem(void *vaddr)
	{
		uint64_t tmp[2];
		uint32_t size;

		tmp[0] = reinterpret_cast<uint64_t>(vaddr);

		if (mapped_pages.find(vaddr) != mapped_pages.end())
		{
			auto mapped = mapped_pages[vaddr];

			switch (mapped.first.alloc)
			{

			case CoyoteAlloc::RCNFG_2M:

				mLock();

				if (munmap(mapped.second, (mapped.first.n_pages + 1) * hugePageSize) != 0)
				{
					mUnlock();
					throw std::runtime_error("free_pr_mem munmap failed");
				}

				if (ioctl(fd, IOCTL_FREE_HOST_PR_MEM, &vaddr))
				{
					mUnlock();
					throw std::runtime_error("ioctl_free_host_pr_mem failed");
				}

				mUnlock();

				break;

			default:
				throw std::runtime_error("unauthorized memory deallocation, vfid: " + to_string(vfid));
			}

			mapped_pages.erase(vaddr);
		}
	}

	// ======-------------------------------------------------------------------------------
	// Reconfiguration
	// ======-------------------------------------------------------------------------------

	/**
	 * @brief Reconfiguration IO
	 *
	 * @param oid - operator id
	 */
	void cSched::reconfigure(int32_t oid)
	{
		if (bstreams.find(oid) != bstreams.end())
		{
			auto bstream = bstreams[oid];
			reconfigure(std::get<0>(bstream), std::get<1>(bstream));
		}
	}

	/**
	 * @brief Reconfiguration IO
	 *
	 * @param vaddr - bitstream pointer
	 * @param len - bitstream length
	 */
	void cSched::reconfigure(void *vaddr, uint32_t len)
	{
		if (fcnfg.en_pr)
		{
			uint64_t tmp[2];
			tmp[0] = reinterpret_cast<uint64_t>(vaddr);
			tmp[1] = static_cast<uint64_t>(len);
			if (ioctl(fd, IOCTL_RECONFIG_LOAD, &tmp)) // Blocking
				throw std::runtime_error("ioctl_reconfig_load failed");

			DBG3("Reconfiguration completed");
		}
	}

	// Util
	uint8_t cSched::readByte(ifstream &fb)
	{
		char temp;
		fb.read(&temp, 1);
		return (uint8_t)temp;
	}

	/**
	 * @brief Add a bitstream to the map
	 *
	 * @param name - path
	 * @param oid - operator ID
	 */
	void cSched::addBitstream(std::string name, int32_t oid)
	{
		if (bstreams.find(oid) == bstreams.end())
		{
			// Stream
			ifstream f_bit(name, ios::ate | ios::binary);
			if (!f_bit)
				throw std::runtime_error("Bitstream could not be opened");

			// Size
			uint32_t len = f_bit.tellg();
			f_bit.seekg(0);
			uint32_t n_pages = (len + hugePageSize - 1) / hugePageSize;

			// Get mem
			void *vaddr = getMem({CoyoteAlloc::RCNFG_2M, n_pages});
			uint32_t *vaddr_32 = reinterpret_cast<uint32_t *>(vaddr);

			// Read in
			for (uint32_t i = 0; i < len / 4; i++)
			{
				vaddr_32[i] = 0;
				vaddr_32[i] |= readByte(f_bit) << 24;
				vaddr_32[i] |= readByte(f_bit) << 16;
				vaddr_32[i] |= readByte(f_bit) << 8;
				vaddr_32[i] |= readByte(f_bit);
			}

			DBG3("Bitstream loaded, oid: " << oid);
			f_bit.close();

			bstreams.insert({oid, std::make_pair(vaddr, len)});
			return;
		}

		throw std::runtime_error("bitstream with same operation ID already present");
	}

	/**
	 * @brief Remove a bitstream from the map
	 *
	 * @param: oid - Operator ID
	 */
	void cSched::removeBitstream(int32_t oid)
	{
		if (bstreams.find(oid) != bstreams.end())
		{
			auto bstream = bstreams[oid];
			freeMem(bstream.first);
			bstreams.erase(oid);
		}
	}

	/**
	 * @brief Check if bitstream is present
	 *
	 * @param oid - Operator ID
	 */
	bool cSched::checkBitstream(int32_t oid)
	{
		if (bstreams.find(oid) != bstreams.end())
		{
			return true;
		}
		return false;
	}

}
