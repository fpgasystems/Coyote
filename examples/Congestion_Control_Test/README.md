# Changed Files (Coyote)
- **(added) hw/hdl/network/rdma/MT_pomsarc_CC_QP_unit_DCQCN.sv:** DCQCN implementation, tunable parameters for algorithm and for the test run described in file. **`define CC_TEST ** controls wether to compile with the test setting or without.
- **(added) hw/hdl/network/rdma/MT_pomsarc_new _flow.sv:** replaces the old flow control by replacing the request queue with the dcqcn module. This flow control is the "default case" (changes starting Line 160)
- **(added) hw/hdl/network/rdma/MT_pomsarc_new_flow_multiqueue.sv:** the multiqueue version of the flow control commented out. to use thus version comment aut the whole previous file (MT_pomsarc_new _flow.sv) **!!SEE [1] BELOW FOR NOTES**
- **hw/hdl/network/rdma/roce_stack.sv:** added the ecn forward (Line 126, 228 (ila) )
  
- **scripts/wr_hdl/template_gen/lynx_pkg_tmplt.txt:** adjusted the ack interface (Line 197, 432)
- **scripts/ip_inst/network_infrastructure.tcl:** added more ILAs at the bottom

- **hls/ipv4/ipv4.cpp:** added ecn marks to outgoing ecn packets and forward ecn from incoming packets. (Lines: 59, 111, 212) 
# Changed Files (HLS stack)
- **hls/ipv4/ipv4.hpp:** adjusted interface and set/get ecn function (Lines 36, 657)
- **hls/udp/udp.cpp:** same as ipv4 (Lines 173, 195)
- **hls/udp/udp.hpp:** same as ipv4 (Lines 47)
- **hls/ib_transport_protocol/ib_transport_protocol.cpp:** Added the incoming ecn -> outgoing marked ack path and the ecn forwarding to the flow control (Lines: 78, 592, 615, 656, 689, 1533, 1636, 1657, 1687, 1728, 1742, 1779, 2115, 2125, 2365, 2741, 2770)
- **hls/ib_transport_protocol/ib_transport_protocol.hpp:** same as ipv4 (Lines 240, 259, 281)

# Running a Test
To run a test make sure the CC_TEST variable is set in the MT_pomsarc_CC_QP_unit_DCQCN.sv file (not by default). set the Ecn_rates to the different phases, an entry in that array corresponds to the amount of acks not marked between the marked ones. To simulate no marked packets just use a high value (eg. 9999). also adjust the Ecn_rates_max_index variable. compile sw of the Congestion_Control_Test example, exactly the same as example 08. when running set the -o flag to 1 (write) and the -i flag (didnt make sure wether the other flags behave). Run Vivado from the client side. switch to ila 3 (i think, the one with Rc and Rt). select a good amount of trigger windows (i usualy take 2048) and trigger on the 'ila_trigger' AND 'ecn_test_starter' signals equal to 1. ila_trigger goes to 1 in a defined cycle interval and ecn_test_started goes and stays at 1 as soon as the first ack arives. Run the test and export as CSV. CSV file can be input directly to the python script for plotting.

# Notes

- [1] To compile with multiqueue the dreq_t interface array needs to be changed because of non constant indexing (Lines 281, 316/317) im not 100% sure how to fix this (and also cant test it anymore :( )
