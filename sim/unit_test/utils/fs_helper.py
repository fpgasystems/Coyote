import os
from typing import List

class FSHelper:
    """
    Small helper class with FileSystem utility functions
    """

    def get_latest_modification_time(directories: List[str]) -> float:
        """
        Get the latest modification time from all
        files in the given list of directories.
        The time is a floating-point value describing the
        time in seconds since unix epoch of the last
        modification.
        """
        latest_mtime = 0
        for directory in directories:
            for root, _, files in os.walk(directory):
                for file in files:
                    filepath = os.path.join(root, file)
                    mtime = os.path.getmtime(filepath)
                    latest_mtime = max(latest_mtime, mtime)
        return latest_mtime
