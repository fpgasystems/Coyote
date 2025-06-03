from collections.abc import Callable
import threading
import queue
from .exception_group import ExceptionGroup


class SafeThread:
    """
    Implements a thread with:
    - Exception handling. If any exception is thrown in the thread body, those will be re-raised
      when trying to join the thread
    - Termination via an event. E.g. when requesting to join the thread, a cancellation event is
      set, asking the thread to stop, if it is still running.
    - A finished event that can be raised once the thread ran to the end or raised an Exception.
    """

    def __init__(self, target: Callable[[threading.Event], None]):
        """
        Initiates the thread with a call target. The target needs to accept a termination event
        and should finish when the event is set!
        """
        self.target = target
        self.stop_event = threading.Event()
        self.finished_event = threading.Event()
        self.stop_event.clear()
        self.thread = threading.Thread(target=self._safe_target)
        self.thread.daemon = True
        self.exception_queue = queue.Queue()

    def _safe_target(self):
        try:
            # Call the actual function!
            self.target(self.stop_event)
        except Exception as e:
            print(f"Warning: Thread failed with exception: {str(e)}")
            self.exception_queue.put(e)

        # Set finished
        # Either the target finished or ran into an error!
        self.finished_event.set()

    def start(self):
        """
        Starts the thread
        """
        self.thread.start()

    def get_finished_event(self) -> threading.Event:
        """
        Returns an event that is set whenever the thread runs
        to the end. Either because it did all work OR because
        it raised an Exception.

        Please call join once the thread is finished to ensure
        any potential exceptions are caught!
        """
        return self.finished_event

    def join(self):
        """
        Asks the thread to stop and then joins the thread.

        Re-raises any exceptions that might have been thrown
        during the thread execution
        """
        self.stop_event.set()
        self.join_blocking()

    def join_blocking(self):
        """
        Joins the thread without asking it to stop, i.e.
        without rasing the stop event.

        Re-raises any exceptions that might have been thrown
        during the thread execution
        """
        self.thread.join()
        # Check if any exceptions occurred
        if not self.exception_queue.empty():
            error = self.exception_queue.get()
            raise ExceptionGroup("Thread execution failed with errors: ", [error])
