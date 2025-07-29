# Helper script, that for a given mode (shell or app), synthesises all the apps from 9.2. in the Coyote v2 paper
# Additionally, the time taken for the synthesis is recorded

import os
import time

MODE = 'shell'
APPS = ['rdma_aes', 'perf_local', 'mem_vadd']

os.system('mkdir -p builds')

for app in APPS:
    mode_str = '-DBUILD_APP=1 -DBUILD_SHELL=0' if MODE == 'app' else '-DBUILD_APP=0 -DBUILD_SHELL=1'
    
    # NOTE: If the device is changed, the FPLAN_PATH in CMakeLists.txt should also be changed
    ts = time.time()
    os.system(
        f'mkdir -p builds/build_{app}_{MODE} && ' +
        f'cd builds/build_{app}_{MODE} && ' +
        f'rm -rf * &&' +
        f'cmake ../../ -DEXAMPLE={app} -DFDEV_NAME=u250 {mode_str} &&' + 
        f'make project && make bitgen'
    )
    te = time.time()
    
    with open('synth-times.csv', 'a') as f:
        f.write(f'{MODE},{app},{te - ts}\n')
