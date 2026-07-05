# Coyote Utility Scripts

This directory contains three helper scripts for **programming Coyote FPGA bitstreams**, **deploying drivers**, and **launching host applications with correct NUMA binding**.  
They are intended for use on the ETHZ **HACC** cluster (U55C nodes) or compatible systems.


---

## 1. `program_hacc_local.sh`

Programs a **local FPGA** on the current server with a Coyote bitstream and inserts the corresponding Coyote driver.

This script:

- Checks that Vivado is available
- Removes any existing Coyote driver (for safe DMA reset)
- Programs the FPGA via `hdev program vivado`
- Extracts FPGA IP/MAC and converts them automatically for driver parameters
- Inserts the Coyote driver with proper configuration

### **Usage**
```
./program_hacc_local.sh <bitstream_path> <driver_path> <device_id>
```

If `<device_id>` is omitted, the default is `1`.

### **Example**
```
./program_hacc_local.sh build/top.bit drivers/coyote_driver.ko 1
```

### **Notes**

- Must be executed **on the node where the FPGA is physically located**.
- Ensures a clean PCIe state before reprogramming.

---

## 2. `program_hacc_remote.sh`

Programs **remote U55C FPGA nodes** in parallel using `parallel-ssh`.

This script:

1. Prompts the user for a list of U55C node IDs (e.g., `1 3 5`)
2. Converts them into full hostnames (e.g., `alveo-u55c-01`)
3. Invokes `program_hacc_local.sh` on each node using parallel-ssh

### **Usage**
```
./program_hacc_remote.sh <bitstream_path> <driver_path> <device_id>
```

### **Example**
```
./program_hacc_remote.sh build/top.bit drivers/coyote_driver.ko 1
```

Prompt:
```
*** Enter space-separated U55C server IDs:
> 2 4 7
```

Programs:
- `alveo-u55c-02`
- `alveo-u55c-04`
- `alveo-u55c-07`

### **Notes**
- Requires passwordless SSH or valid cluster authentication.
- Must be executed from the same directory as `program_hacc_local.sh`.

---



## 1. `launch_with_numa_bound.sh`

A utility script to run any host program **bound to the NUMA node** of a given Coyote FPGA device.

The script automatically:

1. Queries PCIe BDF with `hdev get bdf`
2. Resolves the NUMA node from `/sys/bus/pci/devices/.../numa_node`
3. Retrieves the CPU list associated with that NUMA node
4. Launches the user command with:
   ```
   numactl --cpunodebind=<node> --membind=<node>
   ```

### **Usage**
```
./launch_with_numa_bound.sh <DEVICE_ID> <command> [args...]
```

### **Example**
```
./launch_with_numa_bound.sh 1 ./host_app -t 16 -w 32
```

### **Dependencies**
- `hdev`
- `numactl`
- `lscpu`

---