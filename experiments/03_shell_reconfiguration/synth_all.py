# Utility script that will synthesize all the partial bitstreams from 9.3 in the Coyote v2 paper

import os

DEVICE = 'u55c'

folders = [
    'case_1/shell_mmu_2mb',
    'case_1/shell_mmu_1gb',
    'case_2/shell_rdma',
    'case_2/shell_vector_ops',
    'case_3/shell_rdma',
    'case_3/shell_traffic_sniffer'
]

for x in folders:
    os.system(
        f'cd {x} && ' +
        f'mkdir -p build && cd build && rm -rf * && ' +
        f'/bin/cmake ../ && ' +
        f'make project && make bitgen'
    )
