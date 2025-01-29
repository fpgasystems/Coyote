# Enzian ECI toolkit

This repository contains modules that are used to process ECI messages:
 * axi_eci_bridge.vhd - simple AXI <-> ECI bridge, translates AXI read/write requests to ECI RLDT/RSTT messages
 * bus_buffer.vhd - generic bus buffer (register), 1 clock latency, full bandwidth
 * bus_fifo.vhd - generic bus FIFO, 1 clock latency, full bandwidth
 * eci_axi_bridge.vhd - simple ECI <-> AXI bridge, translates ECI RLDD/RLDX/VICD messages to AXI read/write requests
 * eci_bus_channel_converter.vhd - converter from a 17-word wide bus to an ECI channel
 * eci_channel_buffer.vhd - ECI channel buffer (register), 1 clock latency, full bandwidth
 * eci_channel_bus_converter.vhd - converter from an ECI channel to a 17-word wide bus
 * eci_channel_fifo.vhd - ECI channel FIFO, 1 clock latency, full bandwidth
 * eci_channel_ila.vhd - ECI channel(s) ILA, up to 6 channels
 * eci_channels_muxer.vhd - n:1 ECI channel muxer
 * eci_cmd_defs.sv - various ECI definitions and functions
 * eci_defs.vhd - various ECI definitions and functions
 * eci_gateway.vhd - main ECI module
 * eci_link_rx.vhd - ECI message serializer, individual VC FIFOs
 * eci_link_rx_lite.vhd - ECI message serializer, combined VC FIFOs
 * eci_lo_vc_demux.vhd - ECI low bandwidth (lo) VCs (6-12) filter
 * eci_rx_crossbar.vhd - ECI receiving crossbar switch for individual VCs
 * eci_rx_crossbar_lite.vhd - ECI receiving crossbar switch for combined VCs
 * eci_rx_hi_vc_extractor.vhd - ECI high bandwidth (hi) VCs (2-5) buffer and downmix
 * eci_rx_hi_vc_packetizer.vhd - ECI high bandwidth (hi) VCs (2-5) packet finder
 * eci_rx_io_vc_filter.vhd - ECI frames filter, filter out everything except VCs 0, 1 and 13
 * eci_rx_vc_filter.vhd - ECI messages VC-based filter
 * eci_rx_vc_word_extractor.vhd - ECI lo VC messages serializer
 * eci_rx_vc_word_extractor_buffered.vhd - buffered ECI lo VC messages serializer (1 cycle latency)
 * eci_tx_crossbar.vhd - ECI transmitting crossbar switch
 * loopback_vc_resp_nodata.sv - ECI GSYNC/GINV/GSDN simple loopback handler
 * rx_credit_counter.vhd - receiving credit counter
 * tlk_credits.vhd - transmitting credit counters
