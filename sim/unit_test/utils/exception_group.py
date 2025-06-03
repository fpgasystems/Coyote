
# Mimics the existing ExceptionGroup from Python > 3.8
from typing import List
from io import StringIO
import traceback

class ExceptionGroup(Exception):
    def __init__(self, message: str, exceptions: List[Exception]):
        assert isinstance(exceptions, list), "Exception group expected list of Exceptions"
        self.message = message
        self.exceptions = exceptions
        super().__init__(message, exceptions)

    def __str__(self):
        output = StringIO()
        output.write(f"{self.message} ({len(self.exceptions)} exceptions):\n")

        for i, exception in enumerate(self.exceptions):
            output.write(f"\t[{i+1}] {exception}\n")
            if exception.__traceback__:
                tb = traceback.format_tb(exception.__traceback__)
                for line in tb:
                    output.write(f"\t\t{line}\n")
        
        return output.getvalue()