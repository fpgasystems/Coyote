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
        self.callback = None
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
            print(f"CRITICAL ERROR: Thread execution failed with exception: {str(e)}")
            self.exception_queue.put(e)
            self._trigger_error_callback()

        # Set finished
        # Either the target finished or ran into an error!
        self.finished_event.set()

    def _trigger_error_callback(self):
        if self.callback is None:
            return

        try:
            self.callback()
        except Exception as e:
            print(
                "CRITICAL ERROR: Error handling routine " +
                f"of SafeThread threw another error: {str(e)}"
            )

    def start(self):
        """
        Starts the thread
        """
        self.thread.start()

    def register_error_call_back(self, callback: Callable[[None], None]) -> None:
        """
        Registers a function that is called if the thread
        terminates prematurely because a error was raised.

        Should the callback itself cause a error the error
        will be logged but not raised.
        """
        self.callback = callback

    def get_finished_event(self) -> threading.Event:
        """
        Returns an event that is set whenever the thread runs
        to the end. Either because it did all work OR because
        it raised an Exception.

        Please call join once the thread is finished to ensure
        any potential exceptions are caught!
        """
        return self.finished_event

    def terminate_and_join(self):
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
