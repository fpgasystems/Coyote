######################################################################################
# This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
# 
# MIT Licence
# Copyright (c) 2025, Systems Group, ETH Zurich
# All rights reserved.
# 
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:

# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.

# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
######################################################################################

from enum import Enum
from typing import TypeVar
import re

SimTime = TypeVar("T", bound="SimulationTime")
SimTimeUnit = TypeVar("T", bound="SimulationTimeUnit")
FixedSimTime = TypeVar("T", bound="FixedSimulationTime")


class SimulationTimeUnit(Enum):
    # Important: The numbers need to
    # increase 1 by 1 from the smallest
    # to the largest unit. This property
    # is assumed in the conversion function below
    FEMTOSECONDS = 1
    PICOSECONDS = 2
    NANOSECONDS = 3
    MICROSECONDS = 4
    MILLISECONDS = 5
    SECONDS = 6

    def __str__(self):
        match self:
            case SimulationTimeUnit.FEMTOSECONDS:
                return "fs"
            case SimulationTimeUnit.PICOSECONDS:
                return "ps"
            case SimulationTimeUnit.NANOSECONDS:
                return "ns"
            case SimulationTimeUnit.MICROSECONDS:
                return "us"
            case SimulationTimeUnit.MILLISECONDS:
                return "ms"
            case SimulationTimeUnit.SECONDS:
                return "sec"
            case _:
                raise ValueError(f"Unknown SimulationTimeUnit: {self.name}")

    @staticmethod
    def from_string(string: str) -> SimTimeUnit:
        match string:
            case "fs":
                return SimulationTimeUnit.FEMTOSECONDS
            case "ps":
                return SimulationTimeUnit.PICOSECONDS
            case "ns":
                return SimulationTimeUnit.NANOSECONDS
            case "us":
                return SimulationTimeUnit.MICROSECONDS
            case "ms":
                return SimulationTimeUnit.MILLISECONDS
            case "sec":
                return SimulationTimeUnit.SECONDS
            case _:
                raise ValueError(f"Unknown SimulationTimeUnit: {string}")


class SimulationTime:
    def __init__(self, time: str):
        """
        Sets the simulation time string for the vivado run command
        according to the Vivado documentation:
        https://docs.amd.com/r/en-US/ug835-vivado-tcl-commands/run.

        Do NOT use this constructor directly. Instead, use the static
        convenience methods.
        """
        self._time = time

    def get_simulation_time(self) -> str:
        return self._time

    @staticmethod
    def fixed_time(time: int, unit: SimulationTimeUnit) -> SimTime:
        """
        Runs the simulation for a fixed time as given to this method
        """
        assert isinstance(time, int)
        assert isinstance(unit, SimulationTimeUnit)
        return FixedSimulationTime(time, unit)

    def till_finished() -> SimTime:
        """
        Runs the simulation until an exception is encountered or
        no events are left in the queue.
        In order words: Till the last output was received.
        Caution: For this to work your design needs to properly
        assert tlast!
        """
        return SimulationTime("-all")


class FixedSimulationTime(SimulationTime):
    def __init__(self, time: int, unit: SimulationTimeUnit):
        super().__init__(f"{time}{str(unit)}")
        self.time = time
        self.unit = unit

    def convert_to_unit(self, unit: SimulationTimeUnit) -> int:
        """
        Converts the object begin called into the given SimulationTimeUnit.

        Requires the unit of the calling object to be at least
        as precise as the target unit, otherwise the conversion will fail.
        """
        assert self.unit.value >= unit.value, (
            f"Cannot covert {self.unit.name} to {unit.name}"
        )
        factor = pow(1000, self.unit.value - unit.value)
        return self.time * factor

    @staticmethod
    def from_string(time_string: str) -> FixedSimTime:
        match = re.match(r"^([0-9]+)(\w+)$", time_string)
        if not match:
            raise ValueError(f"Could not parse FixedSimulationTime {time_string}")

        amount = int(match.group(1))
        unit = SimulationTimeUnit.from_string(match.group(2))
        return FixedSimulationTime(amount, unit)
