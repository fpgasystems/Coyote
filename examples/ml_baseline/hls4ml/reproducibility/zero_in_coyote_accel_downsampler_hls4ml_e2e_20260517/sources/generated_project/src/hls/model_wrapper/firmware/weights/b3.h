//Numpy array shape [8]
//Min -0.031250000000
//Max 0.046875000000
//Number of zeros 0

#ifndef B3_H_
#define B3_H_

#ifndef __SYNTHESIS__
bias3_t b3[8];
#else
bias3_t b3[8] = {0.0312500, 0.0234375, -0.0312500, 0.0468750, -0.0078125, 0.0234375, 0.0078125, -0.0078125};

#endif

#endif
