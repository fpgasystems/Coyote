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

import subprocess
import os
import pty
import logging
import pickle
from collections.abc import Callable
from io import StringIO
from pathlib import Path
from signal import Signals
import threading
from typing import List, Dict
import select
import atexit

from .constants import (
    SIM_FOLDER,
    UNIT_TEST_FOLDER,
    SOURCE_FOLDER,
    TEST_BENCH_FOLDER,
    COMPILE_CHECK_FILE,
    SIM_TARGET_V_FPGA_TOP_FILE,
    VIVADO_BINARY_PATH,
    PROJECT_NAME
)
from .simulation_time import SimulationTime
from .utils.fs_helper import FSHelper


def _get_env():
    env = os.environ.copy()
    env["TERM"] = "xterm"
    return env


class ProcessRunner:
    def run_bash_script(self, path: str):
        result = subprocess.run(["/bin/bash", path], cwd=os.getcwd(), env=_get_env())
        assert result.returncode == 0, f"Running bash script at {path} failed"

    def try_open_file_in_vscode(self, filepath):
        subprocess.run(
            ["code", "-g", filepath], env=_get_env(), capture_output=False, text=False
        )


class Singleton(type):
    _instances = {}

    def __call__(cls, *args, **kwargs):
        if cls not in cls._instances:
            cls._instances[cls] = super(Singleton, cls).__call__(*args, **kwargs)
        return cls._instances[cls]


class CompilationInfo:
    """
    This class captures all the information needed to decide whether
    a recompilation of the project is required.
    Using the method 'requires_compilation', one can determine if 
    a new compilation is required given a CompilationInfo object from the last
    time the project was compiled.
    """
    def __init__(
        self, max_change_time: float, vfpga_top_file: str, defines: Dict[str, str]
    ):
        """
        Captures all the information needed to decide whether the project needs to be re-compiled.

        max_change_time = The latest modification time of any of the relevant
            as a floating-point number representing the time in seconds since unix epoch
        vfpga_top_file  = The path to the vfpga_top_file to be used.
        defines         = A dictionary of the defines that the project should be compiled with. 

        """
        self.max_change_time = max_change_time
        self.vfpga_top_file = vfpga_top_file
        self.defines = defines

    def get_change_time(self) -> float:
        return self.max_change_time

    def get_vfpga_file(self) -> float:
        return self.vfpga_top_file

    def get_defines(self) -> Dict[str, str]:
        return self.defines

    def requires_recompilation(self, previous):
        """
        Given self and the previous compilation info,
        tells you whether recompilation is required
        """
        time = previous.get_change_time() < self.get_change_time()
        vfpga = previous.get_vfpga_file() != self.get_vfpga_file()
        defines = previous.get_defines() != self.get_defines()

        return time or vfpga or defines

    def defines_to_vivado_str(self) -> str:
        """
        Returns a string representing the defines.
        The string can be used in the vivado set_property command
        """
        # See the format here:
        # https://docs.amd.com/r/en-US/ug900-vivado-logic-simulation/xelab-xvhdl-and-xvlog-xsim-Command-Options
        return " ".join(f"-d {k}={v}" for k, v in self.defines.items())


# A singleton that is only create ONCE for all tests
# This allows us to share the compilation & elaboration
# steps between test to cut down on test run-time!
VIVADO_CLI_START = "Vivado% "
VIVADO_NEW_LINE = "\r\n"


class VivadoRunner(metaclass=Singleton):
    def __init__(self):
        self._ensure_initialized_state()
        # Setup logging
        self.logger = logging.getLogger("Vivado")
        self.logger.addHandler(logging.StreamHandler(self.log_buffer))
        # Ensure proper termination
        atexit.register(self._terminate_vivado)

    def _ensure_initialized_state(self):
        if hasattr(self, "vivado") and self.vivado is not None:
            return

        # Set state variables
        self.project_open = False
        self.buffered_vivado_log = ""
        self.log_buffer = StringIO()

        # We need to emulate a tty for vivado to
        # output "Vivado%", so we can know when a
        # command execution finishes
        self.tty_master_fd, self.tty_slave_fd = pty.openpty()
        self.vivado = subprocess.Popen(
            [VIVADO_BINARY_PATH, "-mode", "tcl"],
            stdin=self.tty_slave_fd,
            stdout=self.tty_slave_fd,
            # Pipe stderr to stdout to have one stream!
            # -> We will check errors in some other way
            stderr=self.tty_slave_fd,
            text=True,
            cwd=SIM_FOLDER,
            env=_get_env(),
            # This includes vivado in a new process group,
            # which allows us to terminate it and all sub-processes on exit
            preexec_fn=os.setsid,
            bufsize=1,
        )

    def _terminate_vivado(self):
        """
        Tries to terminate a running vivado process.
        If the process does not exit within 5 seconds,
        it is killed.

        Returns immediately if vivado is not running.
        """
        if not hasattr(self, "vivado") or self.vivado is None:
            return

        # 1. terminate the vivado process
        self._quit_vivado()

        # Get the id of the whole process group
        process_group_id = os.getpgid(self.vivado.pid)
        try:
            # Try to terminate vivado and all subprocesses
            os.killpg(process_group_id, Signals.SIGTERM)
            self.vivado.wait(timeout=5)
        except (subprocess.TimeoutExpired, ProcessLookupError, OSError):
            # Force kill the entire process group if they did not exit properly
            try:
                os.killpg(os.getpgid(process_group_id), Signals.SIGKILL)
            except (ProcessLookupError, OSError):
                # If this happens, the processed died before
                pass

        # 2. close all file descriptor
        os.close(self.tty_master_fd)
        os.close(self.tty_slave_fd)

        # Indicate vivado has been killed
        self.vivado = None

    def _try_read_till_stop(self, fd: int, stop_event: threading.Event) -> str:
        """
        Tries to read output from the given fd. Stops trying when stop_event is set.
        Returns the output if the read succeeded and a empty string otherwise.
        """
        while not stop_event.is_set():
            ready, _, _ = select.select([fd], [], [], 0.1)
            if ready:
                try:
                    return os.read(fd, 1024).decode()
                except OSError:
                    break
        return ""

    def _accumulate_vivado_output_to_log(self, output: str) -> None:
        # We buffer the output until we find a new-line character
        # Otherwise, we log half lines all the time
        without_vivado = output.replace(VIVADO_CLI_START, "")
        self.buffered_vivado_log += without_vivado
        if VIVADO_NEW_LINE in self.buffered_vivado_log:
            if self.buffered_vivado_log.endswith(VIVADO_NEW_LINE):
                # If the output ends in a newline, flush everything!
                self._flush_vivado_log_output()
            else:
                # Otherwise: only flush those lines that contain new lines
                to_flush = self.buffered_vivado_log.split(VIVADO_NEW_LINE)
                self._flush_lines(to_flush[:-2])
                self.buffered_vivado_log = to_flush[-1]

    def _flush_lines(self, lines: List[str]) -> None:
        without_empty_lines = filter(lambda x: x != "", lines)

        for line in without_empty_lines:
            self.logger.info(line)

    def _flush_vivado_log_output(self) -> None:
        self._flush_lines(self.buffered_vivado_log.split(VIVADO_NEW_LINE))
        self.buffered_vivado_log = ""

    def _keep_last_n_characters(self, n: int, existing: str, new: str) -> str:
        keep_characters = n - len(new)
        return existing[-keep_characters:] + new

    def _wait_till_vivado_is_ready(self, stop_event: threading.Event) -> str:
        """
        Waits till vivado is ready for the next command.
        Returns the last line character produced by the output
        """
        last_20_output_chars = ""
        # Read the response
        while not stop_event.is_set():
            lines = self._try_read_till_stop(self.tty_master_fd, stop_event)
            self._accumulate_vivado_output_to_log(lines)

            # Keep the last 20 characters of output.
            # This is needed because the VIVADO_CLI_START
            # can be spread over multiple reads
            last_20_output_chars = self._keep_last_n_characters(
                20, last_20_output_chars, lines
            )

            # Check if command ran till the end
            if VIVADO_CLI_START in last_20_output_chars:
                break

        self._flush_vivado_log_output()

        # Return last character before vivado terminated, if any exists!
        last_20_output_chars = last_20_output_chars.replace(
            VIVADO_CLI_START, ""
        ).replace(VIVADO_NEW_LINE, "")
        if len(last_20_output_chars) > 0:
            return last_20_output_chars[-1]
        return ""

    def _run_in_vivado(self, command, stop_event: threading.Event) -> str:
        """
        Pipes the given command into std in and
        returns the last output line returned by vivado
        """
        # Send the command
        os.write(self.tty_master_fd, (command + "\n").encode())
        return self._wait_till_vivado_is_ready(stop_event)

    def _quit_vivado(self):
        os.write(self.tty_master_fd, ("quit\n").encode())

    def _run_command(self, command: str, stop_event: threading.Event) -> bool:
        """
        Runs the given command and returns whether the execution was successful
        """
        self.logger.info(command)
        output = self._run_in_vivado(f"catch {{{command}}} execution_error", stop_event)
        if output == "1":
            self.logger.error("ERROR DURING COMMAND:")
            self._run_in_vivado("puts $execution_error", stop_event)
            return False

        return True

    def _run_commands(self, commands: List[str], stop_event: threading.Event) -> bool:
        for command in commands:
            if not self._run_command(command, stop_event):
                return False

        return True

    def _get_last_compile_info(self) -> CompilationInfo:
        """
        Loads the last modification time from the
        COMPILE_CHECK_FILE, if it exists.
        The time is a floating-point value describing the
        time in seconds since unix epoch of the last
        modification.
        Returns 0 if the file did not exist.
        """
        try:
            with open(COMPILE_CHECK_FILE, "rb") as file:
                elem = pickle.load(file)
                assert isinstance(elem, CompilationInfo)
                return elem

        except FileNotFoundError:
            return CompilationInfo(0, None, {})

    def _safe_current_compile_info(self, info: CompilationInfo) -> None:
        with open(COMPILE_CHECK_FILE, "wb") as file:
            pickle.dump(info, file)

    def _run_simulation(
        self,
        sim_dump_path,
        simulation_time: SimulationTime,
        stop_event: threading.Event,
    ) -> bool:
        # We could try the following to enable faster simulations (did not change anything for me):
        # set_property -name {xsim.compile.xvlog.more_options} -value {-d SIM_SPEED_UP} -objects [get_filesets sim_1]

        # Ensure path ends in slash
        if sim_dump_path != "" and not sim_dump_path.endswith("/"):
            sim_dump_path += "/"

        return self._run_commands(
            [
                # 1. Start simulation, but dont run it
                # This is achieved by setting the runtime value to {}
                # This is needed to capture all output in the vcd
                # -> The VCD cannot be initialized before we launch a simulator and if we only do it afterward, output is missing.
                # -> Therefore, we start a simulator, setup the vcd capture, and only then run it
                "set_property -name {xsim.simulate.runtime} -value {} -objects [get_filesets sim_1]",
                "launch_simulation -simset [get_filesets sim_1] -step simulate -mode behavioral",
                # 2. Restart sim
                "restart",
                # Generate VCD dump for the simulation!
                f"open_vcd {UNIT_TEST_FOLDER}/sim_dump.vcd",
                f"log_vcd /tb_user/inst_DUT/{sim_dump_path}*",
                f"run {simulation_time.get_simulation_time()};",
                "close_vcd",
                "close_sim",
            ],
            stop_event,
        )

    def _open_project(self, stop_event: threading.Event) -> bool:
        """
        Opens the project, if not already open
        """
        if self.project_open:
            return True

        # Ensure the custom VFPGA file exists
        top_file = Path(SIM_TARGET_V_FPGA_TOP_FILE)
        if not top_file.is_file():
            top_file.touch()

        # First command, we need to wait till vivado is ready!
        self._wait_till_vivado_is_ready(stop_event)
        success = self._run_commands(
            [
                # First: open the project
                f"open_project {PROJECT_NAME}.xpr",
                # Second: Replace the vfpga_top.svh file with a file we control
                "remove_files [get_files vfpga_top.svh]",
                f"add_files -fileset [get_filesets sim_1] {SIM_TARGET_V_FPGA_TOP_FILE}",
            ],
            stop_event,
        )
        self.project_open = success
        return success

    def _get_current_compilation_info(
        self, vfpga_top_path: str, defines: Dict[str, str]
    ):
        latest_modification_time = FSHelper.get_latest_modification_time(
            [TEST_BENCH_FOLDER, SOURCE_FOLDER, vfpga_top_path]
        )
        return CompilationInfo(latest_modification_time, vfpga_top_path, defines)

    def _compile_project(
        self,
        vfpga_top_path: str,
        defines: Dict[str, str],
        disable_randomization: bool,
        stop_event: threading.Event,
    ) -> bool:
        # 1. Open the project (if not already open)
        if not self._open_project(stop_event):
            return False

        # Add defines for the randomization
        if not disable_randomization:
            defines["EN_RANDOMIZATION"] = "1"

        # Check if any file changed and we need to recompile!
        last_info = self._get_last_compile_info()
        current_info = self._get_current_compilation_info(vfpga_top_path, defines)

        # 3. Recompile if needed
        if current_info.requires_recompilation(last_info):
            self.logger.info("Recompilation is required.")

            # Copy over the FPGA file
            with open(vfpga_top_path, "r") as src_file:
                with open(SIM_TARGET_V_FPGA_TOP_FILE, "w") as target_file:
                    target_file.write(src_file.read())

            # Compile
            success = self._run_commands(
                [
                    f"set_property -name xsim.compile.xvlog.more_options -value {{{current_info.defines_to_vivado_str()}}} -objects [get_filesets sim_1]",
                    # Increase parallelism for compilation to 16 sub-jobs
                    "set_property -name xsim.compile.xsc.mt_level -value {16} -objects [get_filesets sim_1]",
                    # Set compilation order, Elaborate and compile
                    "update_compile_order -fileset sources_1",
                    "launch_simulation -simset [get_filesets sim_1] -step compile -mode behavioral",
                    "launch_simulation -simset [get_filesets sim_1] -step elaborate -mode behavioral",
                ],
                stop_event,
            )
            if success:
                self._safe_current_compile_info(current_info)
            return success

        self.logger.warning(
            "Skipping recompilation as no source code changes were found."
        )
        return True

    def _run_till_failure_or_stopped(
        self, commands: List[Callable[[None], bool]], stop_event: threading.Event
    ) -> bool:
        """
        Runs the given list of commands in the given order.
        """
        for command in commands:
            if not command():
                if stop_event.is_set():
                    self._terminate_vivado()
                return False

        return True

    def _fatal_errors_in_log(self, log: str) -> bool:
        """
        Returns whether logs with "Fatal: [...]" could be found in
        the given log string
        """
        lines = log.split("\n")
        fatal = list(filter(lambda x: x.startswith("Fatal: "), lines))
        return len(fatal) > 0

    #
    # Public methods
    #
    def run_simulation(
        self,
        vfpga_top_replacement: str,
        sim_dump_path: str,
        simulation_time: SimulationTime,
        disable_randomization: bool,
        defines: Dict[str, str],
        stop_event: threading.Event,
    ) -> bool:
        """
        vfpga_top_replacement = Path to the vfpga_top to use for hte simulation
        sim_dump_path = The module path of what should be included in the vcd dump
            e.g., "db_pipeline/inst_filter"
        simulation_time = The maximum time to run the simulation for, if it does not finish
            earlier. This time is set to prevent the simulation to run forever and needs
            to be increased for long-running tests with large/in-output as it determines
            the maximum simulation run-time.
        disable_randomization = Whether to disable timing randomization for the in & output streams.
            By default, the randomization is enabled as it is good for finding timing issues in the
            design.
        defines = Dictionary of key-value pairs that provide additional definitions. This can be used
            to change parameters in the design for tests. A empty dictionary will not set any
            additional defines.
        stop_event = Event asking for cancellation of the run
        """
        # Ensure vivado is running (might have been terminated in pervious test)
        self._ensure_initialized_state()

        # Run the commands below, one after each other till one fails or stop was triggered
        success = self._run_till_failure_or_stopped(
            [
                lambda: self._compile_project(
                    vfpga_top_replacement, defines, disable_randomization, stop_event
                ),
                lambda: self._run_simulation(
                    sim_dump_path, simulation_time, stop_event
                ),
            ],
            stop_event,
        )

        # Even if the simulation ran successfully, there can be fatal
        # errors in the log. The reason is that when a fatal error
        # occurs, from the view of vivado, the "launch_simulation"
        # command was successfully executed.
        if success and self._fatal_errors_in_log(self.log_buffer.getvalue()):
            self.logger.error("Found FATAL error in simulation execution")
            return False

        return success
