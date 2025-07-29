# Helper script, that will generate the shell checkpoints for the app flow synthesis

import os

APPS = ['rdma_aes', 'perf_local', 'mem_vadd']

os.system('mkdir -p shells')

for app in APPS:
    mode_str = ''
    
    # NOTE: If the device is changed, the FPLAN_PATH in CMakeLists.txt should also be changed
    os.system(
        f'mkdir -p shells/{app} && ' +
        f'cd shells/{app} && ' +
        f'rm -rf * &&' +
        f'cmake ../../ -DEXAMPLE={app} -DFDEV_NAME=u250 -DBUILD_APP=0 -DBUILD_SHELL=1 -DEN_PR=1 &&' + 
        f'make project && make bitgen'
    )
    