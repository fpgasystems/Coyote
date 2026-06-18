# 9.6. Neural network inference

This directory contains the software and hardware source code for the results of Section 9.6. of the SOSP paper: *Coyote v2: Raising the Level of Abstraction for Data Center FPGAs*.
Getting-started examples on Coyote, with more comments and in-depth tutorials can be found in the `examples/` folder.

The integration with [hls4ml](https://github.com/fastmachinelearning/hls4ml) was done as part of the hls4ml library, as a new backend to it. The reason for this is, that Coyote as a platform, already provides the necessary infrastructure to deploy FPGA applications, but it simply needed to be integrated as an hls4ml backend, leveraging all of the neural network optimizations and kernel. 

The pull request (PR) introducing this feature can be found on GitHub: https://github.com/fastmachinelearning/hls4ml/pull/1347.

For those wishing to run the code for this experiment, they should follow the next steps:

1. Check out the hls4ml code from the above-mentioned PR, using for e.g., git, GitHub CLI or similar, making sure submodules are initialized. **NOTE:** Initalizing the submodules is very important, without the following error will be observed:
```
By not providing "FindCoyoteHW.cmake" in CMAKE_MODULE_PATH this project has
asked CMake to find a package configuration file provided by "CoyoteHW",
but CMake did not find one.

Could not find a package configuration file provided by "CoyoteHW" with any
of the following names:
```

2. Install the hls4ml Python package locally (advisable to do this inside a virtual environment):
```
pip install pyparsing

# Install TensorFlow and Keras for loading the ML model
pip install scikit-learn tensorflow==2.12.0 keras==2.12.0

# Install QKeras, to be able to load the quantized model
pip install git+https://github.com/google/qkeras.git

# Install hls4ml
cd hls4ml && pip install -e .
```

3. We provide an example of a pre-trained model for network intrusion detection, as described in the paper. However, the data set must be obtained from the [UNSW-NB15 data set source](https://zenodo.org/records/4519767). The references in the paper can act as a guide for obtaining and pre-processing the dataset. Alternatively, one can use random inputs, if only latency and throughput (but not accuracy) are of interest.

4. The example script, `run_synthesis.py` can be used to convert the quantized model into an hls4ml model and run synthesis. Hardware synthesis can take hours, and hence, should be done using Linux utilities such as `tmux` or `screen` if using a remote server. **NOTE:** The script cannot be run out of the box, as one should make minor modifications specifying the path of the data set (or tweaking it to use random inputs.)

5. Once synthesis is complete, the example script `run_inference.py` can be used to run model inference. If not using the [ETHZ HACC cluster](https://github.com/fpgasystems/hacc/tree/main), the bitstream and driver must be loaded manually. For this, please refer to the [Coyote documentation.](https://fpgasystems.github.io/Coyote/intro/quick-start.html#deploying-coyote)