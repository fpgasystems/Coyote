from enum import Enum
from typing import TypeVar

SimTime = TypeVar('T', bound='SimulationTime')

class SimulationTimeUnit(Enum):
    FEMTOSECONDS = 1
    PICOSECONDS = 2
    NANOSECONDS = 3
    MICROSECONDS = 4
    MILLISECONDS = 5
    SECONDS = 6

    def __str__(self):
        if self == SimulationTimeUnit.FEMTOSECONDS:
            return "fs"
        elif self == SimulationTimeUnit.PICOSECONDS:
            return "ps"
        elif self == SimulationTimeUnit.NANOSECONDS:
            return "ns"
        elif self == SimulationTimeUnit.MICROSECONDS:
            return "us"
        elif self == SimulationTimeUnit.MILLISECONDS:
            return "ms"
        elif self == SimulationTimeUnit.SECONDS:
            return "sec"
        else:
            raise ValueError(f"Unknown SimulationTimeUnit: {self.name}")

class SimulationTime():
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
        return SimulationTime(f"{time}{str(unit)}")

    def till_finished() -> SimTime:
        """
        Runs the simulation until an exception is encountered or
        no events are left in the queue.
        In order words: Till the last output was received.
        Caution: For this to work your design needs to properly
        assert tlast!
        """
        return SimulationTime("-all")
