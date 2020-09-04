`ifndef REQ_ASSIGN_SVH_
`define REQ_ASSIGN_SVH_

`define REQ_ASSIGN(s, m)              				\
	assign m.req		= s.req;					\
	assign m.valid 		= s.valid; 					\
	assign s.ready 		= m.ready;

`define DMA_REQ_ASSIGN(s, m)            			\
	assign m.req		= s.req;					\
	assign m.valid 		= s.valid; 					\
	assign s.ready 		= m.ready;					\
	assign s.done 		= m.done;
	
`define DMA_ISR_REQ_ASSIGN(s, m)            		\
	assign m.req		= s.req;					\
	assign m.valid 		= s.valid; 					\
	assign s.ready 		= m.ready;					\
	assign s.done 		= m.done;					\
	assign s.isr_return = m.isr_return;				

`define META_ASSIGN(s, m)              				\
	assign m.data		= s.data;					\
	assign m.valid 		= s.valid; 					\
	assign s.ready 		= m.ready;

`endif