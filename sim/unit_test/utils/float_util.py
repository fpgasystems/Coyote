from decimal import Decimal


def frange(start: float, stop: float, step: float, precision : int= 1):
    """
    floating-point equivalent to the built-in range method for integers.
    Returns a list of floating point numbers that goes form [start, stop)
    in step steps. For this to work properly, one needs to supply a precision.
    This denotes the maximum digits after the comma that the resulting list should have

    start       = Inclusive floating-point number to start at
    stop        = Exclusive floating-point number to stop at
    step        = How much to go in one step. This determines the length of the resulting list.
    precision   = How many digits should there be at most after the comma in the resulting list. 

    For example:
    > frange(0.0, 0.5, 0.1, precision = 1)
    will return
    > [0.0, 0.1, 0.2, 0.3, 0.4]
    """
    assert step > 0, "Step must be not 0"
    assert (
        isinstance(start, float) & isinstance(stop, float) & isinstance(step, float)
    ), "frange will only be correct when used with floating-point numbers"
    # Note: We use decimal here to produce the results as mentioned in the example above.
    # With "normal" fp numbers, you would get a result close to this but not exactly
    # like the above.
    dec_start = Decimal(start)
    dec_stop = Decimal(stop)
    dec_step = Decimal(step)

    result = [start]
    while dec_start + dec_step < dec_stop:
        result.append(round(float(dec_start + dec_step), precision))
        dec_start = dec_start + dec_step

    return result
