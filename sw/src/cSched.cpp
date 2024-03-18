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
	cSched::cSched(int32_t vfid, csDev dev, bool priority, bool reorder)
		: cRnfg(dev), vfid(vfid), priority(priority), reorder(reorder),
		  plock(open_or_create, "vpga_mtx_user_" + vfid),
		  request_queue(taskCmprSched(priority, reorder))
	{
		DBG3("cSched:  ctor called, vfid " << vfid);

		// Cnfg
		uint64_t tmp[2];

		if (ioctl(fd, IOCTL_PR_CNFG, &tmp))
			throw std::runtime_error("ioctl_pr_cnfg() failed, vfid: " + to_string(vfid));

		fcnfg.en_pr = tmp[0];
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

		named_mutex::remove("vfpga_mtx_mem_" + vfid);
	}

	/**
	 * @brief Run the thread
	 *
	 */
	void cSched::runSched()
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
				curr_ctid = curr_req->ctid;
				curr_run = true;
				lck_r.unlock();
				cv_rcnfg.notify_all();

				// Wait for task completion
				unique_lock<mutex> lck_c(mtx_cmplt);
				if (cv_cmplt.wait_for(lck_c, cmplTimeout, [=]
									  { return curr_run == false; }))
				{
					syslog(LOG_NOTICE, "Task completed, %s, ctid %d, oid %d, priority %d\n",
						   (recIssued ? "operator loaded, " : "operator present, "), curr_req->ctid, curr_req->oid, curr_req->priority);
				}
				else
				{
					syslog(LOG_NOTICE, "Task failed, ctid %d, oid %d, priority %d\n",
						   curr_req->ctid, curr_req->oid, curr_req->priority);
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

	void cSched::pLock(int32_t ctid, int32_t oid, uint32_t priority)
	{
		unique_lock<std::mutex> lck_q(mtx_queue);
		request_queue.emplace(std::unique_ptr<cLoad>(new cLoad{ctid, oid, priority}));
		lck_q.unlock();

		unique_lock<std::mutex> lck_r(mtx_rcnfg);
		cv_rcnfg.wait(lck_r, [=]
					  { return ((curr_run == true) && (curr_ctid == ctid)); });
	}

	void cSched::pUnlock(int32_t ctid)
	{
		unique_lock<std::mutex> lck_c(mtx_cmplt);
		if (curr_ctid == ctid)
		{
			curr_run = false;
			cv_cmplt.notify_one();
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
			reconfigureBase(std::get<0>(bstream), std::get<1>(bstream), vfid);
		}
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
				throw std::runtime_error("Shell bitstream could not be opened");
			
			bStream bstream = readBitstream(f_bit);
			f_bit.close();
			DBG3("Bitstream loaded, oid: " << oid);
			

			bstreams.insert({oid, bstream});
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
