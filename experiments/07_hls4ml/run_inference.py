import numpy as np
from tensorflow.keras.models import load_model
from hls4ml.backends.coyote_accelerator.coyote_accelerator_overlay import CoyoteOverlay

from qkeras.utils import _add_supported_quantized_objects 
co = {}; _add_supported_quantized_objects(co)

# Modify as required
BATCH_SIZE = 16
NUM_BATCHES = 15

# Load model, dataset; if path is different, modify as required
model = load_model('models/unsw_quantized.h5', custom_objects=co)
X = np.load('data/unsw_X.npy')[:NUM_BATCHES * BATCH_SIZE].astype(np.float32).reshape(NUM_BATCHES, BATCH_SIZE, -1)

# Create Coyote overlay and load bitstream
overlay = CoyoteOverlay('synth/test')
# overlay.program_hacc_fpga()

for x in X:
    # CPU inference using Keras
    pred_keras_cpu = model.predict(x)

    # FPGA inference
    pred_hls4ml_fpga = overlay.predict(x, (1, ), BATCH_SIZE)
    
    # Functional correctness check between CPU and FPGA
    np.testing.assert_allclose(pred_keras_cpu, pred_hls4ml_fpga, atol=3e-2)
    print('All tests passed!')
