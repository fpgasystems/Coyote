
# Mimics the existing ExceptionGroup from Python > 3.8
class ExceptionGroup(Exception):
    def __init__(self, message, exceptions):
        self.message = message
        self.exceptions = exceptions
        super().__init__(message, exceptions)

    def __str__(self):
        return f"{self.message} ({len(self.exceptions)} exceptions):\n" + "\n".join(
            f"  [{i+1}] {exc}" for i, exc in enumerate(self.exceptions)
        )
