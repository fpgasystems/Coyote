import os
import os.path
from typing import List

class FSHelper:
    """
    Small helper class with FileSystem utility functions
    """

    def get_latest_modification_time(directories_and_files: List[str]) -> float:
        """
        Get the latest modification time from all
        files in the given list of directories or files.
        The given list may contain None elements, which are skipped.
        The time is a floating-point value describing the
        time in seconds since unix epoch of the last
        modification.
        """
        latest_mtime = 0
        for elem in directories_and_files:
            if elem is not None:
                if os.path.isdir(elem):
                    for root, _, files in os.walk(elem):
                        for file in files:
                            filepath = os.path.join(root, file)
                            mtime = os.path.getmtime(filepath)
                            latest_mtime = max(latest_mtime, mtime)
                elif os.path.isfile(elem):
                    mtime = os.path.getmtime(elem)
                    latest_mtime = max(latest_mtime, mtime)
                else:
                    raise ValueError(f"{elem} was neither directory nor file")

        return latest_mtime
