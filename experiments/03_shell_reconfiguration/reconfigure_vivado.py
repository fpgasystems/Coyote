# Helper script to perform full reconfiguration of the board, as shown in 9.3 and Table 3 of the SOSP paper
# This script uses the hdev utility for the HACC cluster at ETH Zurich, which loads the bitstreams and inserts the driver
# Other platform should change the script accordingly

import os
import time
import argparse

parser = argparse.ArgumentParser()
parser.add_argument('-b','--bitstream_path', action='store', type=str, help='Absolute bitstream path')
args = parser.parse_args()

os.system('cd ../../driver && make')

t = time.time()
os.system(f'cd ../../util && bash program_hacc_local.sh {args.bitstream_path} ../driver/build/coyote_driver.ko')
print('Time', time.time() - t)
