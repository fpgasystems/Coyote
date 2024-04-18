# Enzian ECI Transport

The ECI Transport implements the low-level ECI protocols:
 * Physical - 2 links x 12 10.3125Gbps lanes - interface to the high speed serial transmission over differential pairs
 * Data link - Interlaken-based framing protocol
 * Transport - Link handling

## Block diagram
![](doc/img/eci_transport.svg "ECI Link")

### Physical layer
Data is sent over 2 physical links, each consisting of 12 lanes. The total raw bandwidth is 247.5Gbps.
The lanes use 64b/67b word encoding. Each 64-bit word is supplemented by a 2-bit coding word, describing if this is a data word or a control word, and a DC balancing bit.
The ECI Transport uses built-in GTY transceivers to receive and send data and to perform 64b/67b encoding/decoding. The GTY transceivers are set in the low-latency mode to reduce the ECI overall latency.
The bandwidth after the 64b/67b coding is 236.32Gbps or 3694 million words.

### Data link layer
The Interlaken-based framing protocol send data in metaframes, consisting of 2048 words, of which 2044 carry data, and 4 are control words: DIAG, SYNC, SCRAMBLE and SKIP. The SYNC frame is used to align all 12 lanes.
Words from the 12 aligned words from each lane are grouped in 8-word ECI blocks. The data/control word coding is also used to mark the end of an ECI block, the ECI control word.

### Transport layer
An ECI blocks consists of 8 words, 7 words of payload and a control word. The ECI control word consists of a block type (SYNC, DATA, REQ, ACK), 7 VC numbers for each of 7 payload words, an ECI CRC checksum and returned credits.
The ECI block types SYNC, REQ and ACK are used to handle the link state in the Link State Machine.
The link can be in states:
 * REQ - request for ack
 * ACK - acknowledge
 * RUN - running
 * REPLAY - resending ECI blocks

The 7 payload words with 7 VC numbers form an ECI frame passed to the high-level ECI protocol handler.
