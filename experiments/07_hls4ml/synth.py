import os

DEVICE = 'u55c'
ROOT_DIR = '/mnt/scratch/bramhorst/coyote-sosp'

examples = [
    # '01_hbm_scaling',
    # '04_multitenancy',
    # '05_multithreading',
    '06_hyperloglog'
]

for x in examples:
    os.system(
        f'cd {ROOT_DIR}/experiments/{x}/hw/ && ' +
        f'mkdir -p build && cd build && ' +
        f'/bin/cmake ../ && ' +
        f'make project && make bitgen' 
    )
