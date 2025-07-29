# Packet Sniffer

SW side for examples_hw/packet_sniffer: Cooperate with vFPGA and convert captured data into pcap file.

## Parameters
### Main Parameters
- `[--npages | -n] <uint32_t>` The number of huge pages used as packet sniffer buffer (defualt: 8).
- `[--device | -d] <uint32_t>` The ID of device (default: 0).
- `[--vfpga | -v] <uint32_t>` The ID of sniffer vFPGA (default: 0).
- `[--raw-filename | -r] <string>` Filename of raw captured data (default capture.txt).
- `[--pcap-filename | -p] <string>` Filename to save converted pcap data (default: capture.pcap).
- `[--conversion-only | -c] <bool>` Only convert previously captured data (default: false).

### Filter Configuration
- `[--no-ipv4] <bool>` Ignore IPv4 (defalut: false).
- `[--no-ipv6] <bool>` Ignore IPv6 (defalut: false).
- `[--no-arp] <bool>` Ignore ARP (defalut: false).
- `[--no-icmp-v4] <bool>` Ignore ICMP on IPv4 (defalut: false).
- `[--no-icmp-v6] <bool>` Ignore ICMP on IPv6 (defalut: false).
- `[--no-udp-v4] <bool>` Ignore UDP on IPv4 (defalut: false).
- `[--no-udp-payload-v4] <bool>` Ignore UDP Payload on IPv4 (defalut: false).
- `[--no-udp-v6] <bool>` Ignore UDP on IPv6 (defalut: false).
- `[--no-udp-payload-v6] <bool>` Ignore UDP Payload on IPv6 (defalut: false).
- `[--no-tcp-v4] <bool>` Ignore TCP on IPv4 (defalut: false).
- `[--no-tcp-payload-v4] <bool>` Ignore TCP Payload on IPv4 (defalut: false).
- `[--no-roce-v4] <bool>` Ignore RoCEv2 on IPv4 (defalut: false).
- `[--no-roce-payload-v4] <bool>` Ignore RoCEv2 Payload on IPv4 (defalut: false).
        
