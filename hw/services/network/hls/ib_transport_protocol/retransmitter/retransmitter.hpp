/************************************************
Copyright (c) 2019, Systems Group, ETH Zurich.
All rights reserved.

Redistribution and use in source and binary forms, with or without modification,
are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice,
this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
this list of conditions and the following disclaimer in the documentation
and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its contributors
may be used to endorse or promote products derived from this software
without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO,
THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE,
EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
************************************************/
#pragma once

#include "../../axi_utils.hpp"
#include "../ib_transport_protocol.hpp"
using namespace hls;

const uint32_t META_TABLE_SIZE = 2000;

struct retransEvent;

struct retransRelease
{
	ap_uint<16> qpn;
	ap_uint<24> latest_acked_req; //TODO rename?
	retransRelease() {};
	retransRelease(ap_uint<16> qpn, ap_uint<24> psn)
		:qpn(qpn), latest_acked_req(psn) {}
};

struct retransmission
{
	ap_uint<16> qpn;
	ap_uint<24> psn;
	//bool		implicit; //TODO or remove
	retransmission() {}
	retransmission(ap_uint<16> qpn)
		:qpn(qpn), psn(0) {}
	retransmission(ap_uint<16> qpn, ap_uint<24> psn)
		:qpn(qpn), psn(psn) {}
};

struct retransMeta
{
	ap_uint<16> qpn;
	ap_uint<24> psn;
	ibOpCode	opCode;
	retransMeta() {}
	retransMeta(ap_uint<16> qpn, ap_uint<24> psn, ibOpCode op)
		:qpn(qpn), psn(psn), opCode(op){}
};

struct retransAddrLen
{
	ap_uint<48> localAddr;
	ap_uint<48> remoteAddr;
	ap_uint<32> length;
	retransAddrLen() {}
	retransAddrLen(ap_uint<48> laddr, ap_uint<48> raddr, ap_uint<32> len)
		:localAddr(laddr), remoteAddr(raddr), length(len) {}
};

struct retransEntry
{
	ap_uint<16> qpn;
	ap_uint<24> psn;
	ibOpCode	opCode;
	ap_uint<48> localAddr;
	ap_uint<48> remoteAddr;
	ap_uint<32> length;
	retransEntry() {}
	retransEntry(ap_uint<16> qpn, ap_uint<24> psn, ibOpCode op, ap_uint<64> laddr, ap_uint<64> raddr, ap_uint<32> len)
		:qpn(qpn), psn(psn), opCode(op), localAddr(laddr), remoteAddr(raddr), length(len) {}
	retransEntry(retransMeta meta, retransAddrLen addrlen)
		:qpn(meta.qpn), psn(meta.psn), opCode(meta.opCode), localAddr(addrlen.localAddr), remoteAddr(addrlen.remoteAddr), length(addrlen.length) {}
};

struct retransPointerEntry
{
	ap_uint<16>	head;
	ap_uint<16> tail;
	//ap_uint<16> oldest_read_req; //TODO maybe move to fsm
	bool valid;
};

typedef enum {INSERT, RELEASE, RX_RETRANS, TIMER_RETRANS} retransOperation ;

struct pointerMeta
{
	retransOperation	op;
	//ap_uint<16>			qpn;
	ap_uint<24>			psn;
	retransPointerEntry entry;
	pointerMeta() {}
	pointerMeta(retransOperation op, ap_uint<24> psn, retransPointerEntry e)
		:op(op), psn(psn), entry(e) {}
};

struct pointerUpdate
{
	ap_uint<16>	qpn;
	retransPointerEntry entry;
	pointerUpdate() {}
	pointerUpdate(ap_uint<16> qpn, retransPointerEntry e)
		:qpn(qpn), entry(e) {}
};

struct retransMetaEntry
{
	ap_uint<24> psn;
	ap_uint<16> next;
	ibOpCode	opCode;
	ap_uint<48> localAddr;
	ap_uint<48> remoteAddr;
	ap_uint<32> length;
	bool valid;
	bool isTail;
	retransMetaEntry() {}
	retransMetaEntry(retransEntry& e)
		:psn(e.psn), next(0), opCode(e.opCode), localAddr(e.localAddr), remoteAddr(e.remoteAddr), length(e.length), valid(true), isTail(true) {}
	/*retransMetaEntry(ap_uint<24> psn)
		:psn(psn) {}*/
	retransMetaEntry(ap_uint<16> next)
		:next(next) {}
};

struct retransMetaReq
{
	ap_uint<16> idx;
	retransMetaEntry entry;
	bool write;
	bool append;
	retransMetaReq() {}
	retransMetaReq(ap_uint<16> idx)
		:idx(idx), write(false),  append(false) {}
	retransMetaReq(ap_uint<16> idx, ap_uint<16> next)
		:idx(idx), entry(retransMetaEntry(next)), write(false), append(true) {}
	retransMetaReq(ap_uint<16> idx, retransMetaEntry e)
		:idx(idx), entry(e), write(true), append(false) {}
};

struct pointerReq
{
	ap_uint<16>	qpn;
	bool		lock;
	//bool		write;
	pointerReq() {}
	pointerReq(ap_uint<16> qpn)
		:qpn(qpn), lock(false) {}
	pointerReq(ap_uint<16> qpn, bool l)
		:qpn(qpn), lock(l) {}
};

//TODO maybe introduce seperate request streams
template <int INSTID = 0>
void retrans_pointer_table(	stream<pointerReq>&					pointerReqFifo,
					stream<pointerUpdate>&				pointerUpdFifo,
					stream<retransPointerEntry>& 		pointerRspFifo)
{
#pragma HLS PIPELINE II=1
#pragma HLS INLINE off

	static retransPointerEntry ptr_table[MAX_QPS];
#if defined( __VITIS_HLS__)
	#pragma HLS bind_storage variable=ptr_table type=RAM_T2P impl=BRAM
#else
	#pragma HLS RESOURCE variable=ptr_table core=RAM_T2P_BRAM
#endif
	//#pragma HLS DEPENDENCE variable=ptr_table inter false

	static ap_uint<16> pt_lockedQP;
	static bool pt_isLocked = false;
	static bool pt_wait = false;
	static pointerReq pt_req;

	pointerUpdate upd;

	if (!pointerUpdFifo.empty())
	{
		pointerUpdFifo.read(upd);
		ptr_table[upd.qpn] = upd.entry;
		if (pt_lockedQP == upd.qpn)
		{
			pt_isLocked = false;
		}
	}
	else if (!pointerReqFifo.empty() && !pt_wait)
	{
		pointerReqFifo.read(pt_req);
		if (pt_req.lock && pt_isLocked)
		{
			pt_wait = true;
		}
		else
		{
			pointerRspFifo.write(ptr_table[pt_req.qpn]);
			if (pt_req.lock)
			{
				pt_isLocked = true;
				pt_lockedQP = pt_req.qpn;
			}
		}
	}
	else if (pt_wait && !pt_isLocked)
	{
		pointerRspFifo.write(ptr_table[pt_req.qpn]);
		pt_isLocked = true;
		pt_lockedQP = pt_req.qpn;
		pt_wait = false;
	}
}

template <int INSTID = 0>
void retrans_meta_table(stream<retransMetaReq>&		meta_upd_req,
						stream<retransMetaEntry>&		meta_rsp)
{
#pragma HLS PIPELINE II=1
#pragma HLS INLINE off

	static retransMetaEntry meta_table[META_TABLE_SIZE];
#if defined( __VITIS_HLS__)
	#pragma HLS bind_storage variable=meta_table type=RAM_T2P impl=BRAM
#else
	#pragma HLS RESOURCE variable=meta_table core=RAM_T2P_BRAM
#endif
	#pragma HLS DEPENDENCE variable=meta_table inter false

	retransMetaReq req;

    if (!meta_upd_req.empty())
    {
        meta_upd_req.read(req);
        if (req.write)
        {
            meta_table[req.idx] = req.entry;
        }
        else if (req.append)
        {
            meta_table[req.idx].next = req.entry.next;
            meta_table[req.idx].isTail = false;
        }
        else
        {
            meta_rsp.write(meta_table[req.idx]);
        }
    }
}

//TODO HLS is failing so bad with II, such that this module has a ton of states
template <int INSTID = 0>
void process_retransmissions(	stream<retransRelease>&	rx2retrans_release_upd,
					stream<retransmission>& rx2retrans_req,
					stream<retransmission>& timer2retrans_req,
					stream<retransEntry>&	tx2retrans_insertRequest,
					stream<pointerReq>&					pointerReqFifo,
					stream<pointerUpdate>&				pointerUpdFifo,
					stream<retransPointerEntry>& 		pointerRspFifo, //TODO reorder
					stream<retransMetaReq>&				metaReqFifo,
					stream<retransMetaEntry>&			metaRspFifo,
					stream<ap_uint<16> >&				freeListFifo,
					stream<ap_uint<16> >&				releaseFifo,
					//stream<bool>&	stopFifo,
					stream<retransEvent>&				retrans2event)
{
#pragma HLS PIPELINE II=1
#pragma HLS INLINE off

	enum retransStateType {MAIN, INSERT_0, INSERT_1, RELEASE_0, RELEASE_1, RETRANS_0, RETRANS_1, RETRANS_2, TIMER_RETRANS_0, TIMER_RETRANS_1};
	static retransStateType rt_state = MAIN;
	static retransRelease release;
	static ap_uint<16> curr;
	static ap_uint<16> newMetaIdx;
	static retransEntry insert;
	static retransmission retrans;
	static retransMetaEntry meta; //TODO register needed??
	static retransPointerEntry ptrMeta;

	switch (rt_state)
	{
	case MAIN:
		if (!rx2retrans_release_upd.empty())
		{
			rx2retrans_release_upd.read(release);
			pointerReqFifo.write(pointerReq(release.qpn, true));
			rt_state = RELEASE_0;
		}
		else if (!tx2retrans_insertRequest.empty() && !freeListFifo.empty())
		{
			newMetaIdx = freeListFifo.read();
			tx2retrans_insertRequest.read(insert);
			pointerReqFifo.write(pointerReq(insert.qpn, true));
			rt_state = INSERT_0;
		}
		else if (!rx2retrans_req.empty())
		{
			rx2retrans_req.read(retrans);
			std::cout << "RX Retransmit triggered!! , psn: " << std::hex << retrans.psn << std::endl;
			pointerReqFifo.write(pointerReq(retrans.qpn));
			rt_state = RETRANS_0;
		}
		else if (!timer2retrans_req.empty())
		{
			std::cout << "TIMER Retransmit triggered!!\n";
			timer2retrans_req.read(retrans);
			//Uses always head psn
			pointerReqFifo.write(pointerReq(retrans.qpn));
			rt_state = TIMER_RETRANS_0;
		}
		break;
	case INSERT_0:
		if (!pointerRspFifo.empty())
		{
			pointerRspFifo.read(ptrMeta);
			if (!ptrMeta.valid)
			{
				//init entry
				ptrMeta.valid = true;
				ptrMeta.head = newMetaIdx;
				ptrMeta.tail = newMetaIdx;
				metaReqFifo.write(retransMetaReq(newMetaIdx, retransMetaEntry(insert)));
				pointerUpdFifo.write(pointerUpdate(insert.qpn, ptrMeta));
				rt_state = MAIN;
			}
			else
			{
				//Append new pointer to tail
				metaReqFifo.write(retransMetaReq(ptrMeta.tail, newMetaIdx));
				ptrMeta.tail = newMetaIdx;
				rt_state = INSERT_1;
			}
		}
		break;
	case INSERT_1:
		metaReqFifo.write(retransMetaReq(newMetaIdx, retransMetaEntry(insert)));
		pointerUpdFifo.write(pointerUpdate(insert.qpn, ptrMeta));
		rt_state = MAIN;
		break;
	case RELEASE_0:
		if (!pointerRspFifo.empty())
		{
			std::cout << "releasing: " << release.latest_acked_req << std::endl;
			pointerRspFifo.read(ptrMeta);
			if (ptrMeta.valid)
			{
				//Get continuous stream of meta entries
				metaReqFifo.write(retransMetaReq(ptrMeta.head));
				curr = ptrMeta.head;
				rt_state = RELEASE_1;
			}
			else
			{
				std::cout << "RELEASE_0: invalid meta entry\n";
				//Release lock
				pointerUpdFifo.write(pointerUpdate(release.qpn, ptrMeta));
				rt_state = MAIN;
			}
		}
		break;
	case RELEASE_1:
		if (!metaRspFifo.empty())
		{
			//TODO rearrange this thing
			metaRspFifo.read(meta);

			//TODO this should never occur: meta.entry.valid
			std::cout << "meta.psn: " << meta.psn << ", latest acked req: " << release.latest_acked_req << std::endl;
			if (!meta.valid || (meta.psn == release.latest_acked_req))
			{
				if (meta.psn == release.latest_acked_req)
				{
					std::cout << "release success" << std::endl;
				}
				ptrMeta.head = meta.next;
				ptrMeta.valid = !meta.isTail;
				pointerUpdFifo.write(pointerUpdate(release.qpn, ptrMeta));
				rt_state = MAIN;
			}
			else
			{
				if (meta.isTail)
				{
					ptrMeta.valid = false;
					ptrMeta.head = curr;
					pointerUpdFifo.write(pointerUpdate(release.qpn, ptrMeta));
					rt_state = MAIN;
				}
				else
				{
                    metaReqFifo.write(retransMetaReq(meta.next));
				}
				curr = meta.next;
			}
			if (meta.valid)
			{
				releaseFifo.write(curr);
			}
		}
		break;
	case RETRANS_0:
		if (!pointerRspFifo.empty())
		{
			pointerRspFifo.read(ptrMeta);
			//curr = ptrMeta.head;
			rt_state = MAIN;
			if (ptrMeta.valid)
			{
				//Get continuous stream of meta entries
				metaReqFifo.write(retransMetaReq(ptrMeta.head));
				curr = ptrMeta.head;
				rt_state = RETRANS_1;
			}
		}
		break;
	case RETRANS_1:
		//Find PSN of interest and start retransmitting
		if (!metaRspFifo.empty())
		{
			metaRspFifo.read(meta);
			if (meta.valid)
			{
				if (!meta.isTail)
				{
					metaReqFifo.write(retransMetaReq(meta.next));
				}
				else
				{
					rt_state = MAIN;
				}
				//Check if we should start retransmitting
				if (meta.psn == retrans.psn)
				{
					//Generate event
					std::cout << std::hex << "retransmitting opcode: " << meta.opCode << ", local addr: " << meta.localAddr << ", remote addr: " << meta.remoteAddr << ", length: " << meta.length << std::endl;
					retrans2event.write(retransEvent(meta.opCode, retrans.qpn, meta.localAddr, meta.remoteAddr, meta.length, meta.psn));
					if (!meta.isTail)
					{
						rt_state = RETRANS_2;
					}
				}
			}
			else
			{
				rt_state = MAIN;
			}
		}
		break;
	// TODO: can we simplify this state?
	case RETRANS_2:
		//Retransmit everything until we reach tail
		if (!metaRspFifo.empty())
		{
			metaRspFifo.read(meta);
			if (meta.valid)
			{
				if (!meta.isTail)
				{
					metaReqFifo.write(retransMetaReq(meta.next));
				}
				else
				{
					rt_state = MAIN;
				}
				//Generate event
				std::cout << std::hex << "retransmitting opcode: " << meta.opCode << ", local addr: " << meta.localAddr << ", remote addr: " << meta.remoteAddr << ", length: " << meta.length << std::endl;
				retrans2event.write(retransEvent(meta.opCode, retrans.qpn, meta.localAddr, meta.remoteAddr, meta.length, meta.psn));
			}
			else
			{
				rt_state = MAIN;
			}
		}
		break;
	case TIMER_RETRANS_0:
		if (!pointerRspFifo.empty())
		{
			pointerRspFifo.read(ptrMeta);
			if (ptrMeta.valid)
			{
				metaReqFifo.write(retransMetaReq(ptrMeta.head));
				rt_state = TIMER_RETRANS_1;
			}
			else
			{
				rt_state = MAIN;
			}
		}
		break;
	case TIMER_RETRANS_1:
		if (!metaRspFifo.empty())
		{
			meta = metaRspFifo.read();
			if (meta.valid)
			{
				retrans2event.write(retransEvent(meta.opCode, retrans.qpn, meta.localAddr, meta.remoteAddr, meta.length, meta.psn));
			}
			rt_state = MAIN;
		}
		break;
	}//switch
}

template <int INSTID = 0>
void freelist_handler(	stream<ap_uint<16> >& rt_releaseFifo,
						stream<ap_uint<16> >& rt_freeListFifo)
{
#pragma HLS PIPELINE II=1
#pragma HLS INLINE off

	static ap_uint<16> freeListCounter = 0;
	#pragma HLS reset variable=freeListCounter

	if (!rt_releaseFifo.empty())
	{
		rt_freeListFifo.write(rt_releaseFifo.read());
		freeListCounter--;	// TODO: there should be some safeguarding that freeListCounter >= 0, but that shouldn't happen?
	}
	else if (freeListCounter < META_TABLE_SIZE && !rt_freeListFifo.full())
	{
		rt_freeListFifo.write(freeListCounter);
		freeListCounter++;
	}
}

template <int INSTID = 0>
void retransmitter(	stream<retransRelease>&	rx2retrans_release_upd,
					stream<retransmission>& rx2retrans_req,
					stream<retransmission>& timer2retrans_req,
					stream<retransEntry>&	tx2retrans_insertRequest,
					stream<retransEvent>&	retrans2event)
{
//#pragma HLS DATAFLOW
//#pragma HLS INTERFACE ap_ctrl_none register port=return
#pragma HLS INLINE

	static stream<pointerReq>				rt_pointerReqFifo("rt_pointerReqFifo");
	static stream<pointerUpdate>			rt_pointerUpdFifo("rt_pointerUpdFifo");
	static stream<retransPointerEntry> 		rt_pointerRspFifo("rt_pointerRspFifo"); //TODO reorder
	#pragma HLS STREAM depth=2 variable=rt_pointerReqFifo
	#pragma HLS STREAM depth=2 variable=rt_pointerUpdFifo
	#pragma HLS STREAM depth=2 variable=rt_pointerRspFifo

	static stream<retransMetaReq>				rt_metaReqFifo("rt_metaReqFifo");
	static stream<retransMetaEntry>			rt_metaRspFifo("rt_metaRspFifo");
	#pragma HLS STREAM depth=2 variable=rt_metaReqFifo
	#pragma HLS STREAM depth=2 variable=rt_metaRspFifo

	static stream<ap_uint<16> > rt_freeListFifo("rt_freeListFifo");
	#pragma HLS STREAM depth=META_TABLE_SIZE variable=rt_freeListFifo
	static stream<ap_uint<16> > rt_releaseFifo("rt_releaseFifo");
	#pragma HLS STREAM depth=2 variable=rt_releaseFifo

	freelist_handler<INSTID>(rt_releaseFifo, rt_freeListFifo);

	retrans_pointer_table<INSTID>(rt_pointerReqFifo, rt_pointerUpdFifo, rt_pointerRspFifo);

	retrans_meta_table<INSTID>( rt_metaReqFifo,
						rt_metaRspFifo);

	process_retransmissions<INSTID>(rx2retrans_release_upd,
							rx2retrans_req,
							timer2retrans_req,
							tx2retrans_insertRequest,
							rt_pointerReqFifo,
							rt_pointerUpdFifo,
							rt_pointerRspFifo,
							rt_metaReqFifo,
							rt_metaRspFifo,
							rt_freeListFifo,
							rt_releaseFifo,
							retrans2event);
}
