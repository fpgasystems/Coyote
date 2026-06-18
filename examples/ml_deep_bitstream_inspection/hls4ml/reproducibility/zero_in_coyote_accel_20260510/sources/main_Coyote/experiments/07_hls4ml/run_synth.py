import os
import shutil
import numpy as np

from sklearn.metrics import accuracy_score

from tensorflow.keras.models import load_model

from hls4ml.utils import config_from_keras_model
from hls4ml.converters import convert_from_keras_model

from qkeras.utils import _add_supported_quantized_objects 
co = {}; _add_supported_quantized_objects(co)

def build_hls_model(keras_model, X, y, synthesis_id):
    # Create a directory for the model synthesis
    synthesis_directory = 'synth/' + synthesis_id    
    if os.path.isdir(synthesis_directory):
        shutil.rmtree(synthesis_directory)
    os.makedirs(synthesis_directory)

    np.save(f'{synthesis_directory}/X.npy', X)
    np.save(f'{synthesis_directory}/y.npy', y)

    # Create hls4ml config     
    default_precision = 'ap_fixed<12, 4>'
    hls_config = config_from_keras_model(keras_model, granularity='name', default_precision=default_precision)     

    # Conver QKeras model into an hls4ml model
    hls_model = convert_from_keras_model(
                            keras_model, 
                            hls_config=hls_config,
                            output_dir=synthesis_directory, 
                            backend='CoyoteAccelerator',
                            io_type='io_parallel',
                            clock_period=4,
                            input_data_tb=f'{synthesis_directory}/X.npy',
                            output_data_tb=f'{synthesis_directory}/y.npy'
                        )
    hls_model.compile()
    return hls_model

if __name__ == '__main__':
    # Load model and data set
    model = load_model('models/unsw_quantized.h5', custom_objects=co)
    X = np.load('data/unsw_X.npy')[:4096]                   # NOTE: Modify as needed, depending on data location
    y = np.load('data/unsw_y.npy')[:4096].reshape(-1, 1)    # NOTE: Modify as needed, depending on data location
    
    # Run baseline accuracy inference with Keras/TensorFlow
    model.summary()
    pred_tf = model.predict(X)
    
    # Compile hls4ml model and run software emulation
    synthesis_id = 'test'
    hls_model = build_hls_model(model, X, pred_tf, synthesis_id)
    pred_hls = hls_model.predict(X)

    print('TensorFlow accuracy: {}'.format(accuracy_score(np.argmax(y, axis=1), np.argmax(pred_tf, axis=1))))
    print('hls4ml accuracy: {}'.format(accuracy_score(np.argmax(y, axis=1), np.argmax(pred_hls, axis=1))))
    
    # Kick off hardware synthesis
    hls_model.build(csim=True, synth=True, cosim=True, validation=True, timing_opt=True, bitfile=True)
    