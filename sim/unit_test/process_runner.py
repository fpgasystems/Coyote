import subprocess
import os
import pty
import logging
import pickle
import pyprctl
from pathlib import Path
from signal import Signals

from .constants import (
    SIM_FOLDER,
    UNIT_TEST_FOLDER,
    SOURCE_FOLDER,
    TEST_BENCH_FOLDER,
    COMPILE_CHECK_FILE,
    SIM_TARGET_V_FPGA_TOP_FILE
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
    def __init__(self, max_change_time: float, vfpga_top_file: str):
        self.max_change_time = max_change_time
        self.vfpga_top_file = vfpga_top_file

    def get_change_time(self) -> float:
        return self.max_change_time

    def get_vfpga_file(self) -> float:
        return self.vfpga_top_file


# A singleton that is only create ONCE for all tests
# This allows us to share the compilation & elaboration
# steps between test to cut down on test run-time!
class VivadoRunner(metaclass=Singleton):
    def __init__(self):
        self.vivado = self._create_vivado_process(SIM_FOLDER)
        self.project_open = False
        self.logger = logging.getLogger("Vivado")

    def _create_vivado_process(self, folder):
        # We need to emulate a tty for vivado to
        # output "Vivado%", so we can know when a
        # command execution finishes
        self.tty_master_fd, self.tty_slave_fd = pty.openpty()
        return subprocess.Popen(
            ["vivado", "-mode", "tcl"],
            stdin=self.tty_slave_fd,
            stdout=self.tty_slave_fd,
            # Pipe stderr to stdout to have one stream!
            # -> We will check errors in some other way
            stderr=self.tty_slave_fd,
            text=True,
            cwd=folder,
            env=_get_env(),
            # This makes sure the process dies when the calling thread dies!
            # -> We try to cleanup vivado gracefully in the destructor,
            #    but this does not always work. This way we make sure it
            #    always terminates!
            preexec_fn=lambda: pyprctl.set_pdeathsig(Signals.SIGKILL),
            bufsize=1,
        )

    # TODO: Implement in a nicer way
    def _wait_till_vivado_is_ready(self) -> str:
        """
        Waits till vivado is ready for the next command.
        Returns the last line produced by the output
        """
        # Read the response
        output = []
        last_line = ""
        new_line = "\r\n"
        vivado_start = "Vivado% "
        while True:
            try:
                # Read at most 1024 bytes out of the master file_descriptor
                lines = os.read(self.tty_master_fd, 1024).decode()
            except OSError:
                break

            last_line += lines
            if new_line in last_line:
                for line in last_line.replace(vivado_start, "").split(new_line):
                    # Only log full lines!
                    if line != new_line and line != "":
                        self.logger.info(line)

            # Check if vivado finished!
            # Note: The vivado output might be spread over multiple reads.
            # Therefore, we check it with last_line, which can capture
            # multiple read outputs.
            if vivado_start in last_line:
                output.append(lines.replace(vivado_start, ""))
                break

            if new_line in last_line:
                last_line = ""

            output.append(lines)

        if last_line != "" and last_line != new_line and vivado_start not in last_line:
            self.logger.info(last_line)

        # Get the output, which is the final, non empty line, if it exists
        final_output = list(
            filter(
                lambda x: x != "",
                map(lambda x: x.replace(new_line, ""), "".join(output).split(new_line)),
            )
        )
        if len(final_output) > 0:
            return final_output[-1]

        return ""

    def _run_in_vivado(self, command) -> str:
        """
        Pipes the given command into std in and
        returns the last output line returned by vivado
        """
        # Send the command
        os.write(self.tty_master_fd, (command + "\n").encode())
        return self._wait_till_vivado_is_ready()

    def _quit_vivado(self):
        os.write(self.tty_master_fd, ("quit\n").encode())

    def _run_command(self, command) -> bool:
        """
        Runs the given command and returns whether the execution was successful
        """
        self.logger.info(command)
        output = self._run_in_vivado(f"catch {{{command}}} execution_error")
        if output == "1":
            self.logger.error("ERROR DURING COMMAND:")
            self._run_in_vivado("puts $execution_error")
            return False

        return True

    def _run_commands(self, commands) -> bool:
        for command in commands:
            if not self._run_command(command):
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
            return CompilationInfo(0, None)

    def _safe_current_compile_info(self, info: CompilationInfo) -> None:
        with open(COMPILE_CHECK_FILE, "wb") as file:
            pickle.dump(info, file)

    def open_project(self) -> bool:
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
        self._wait_till_vivado_is_ready()
        success = self._run_commands([
            # First: open the project
            "open_project test.xpr",
            # Second: Replace the vfpga_top.svh file with a file we control
            "remove_files [get_files vfpga_top.svh]",
            f"add_files -fileset [get_filesets sim_1] {SIM_TARGET_V_FPGA_TOP_FILE}",
        ])
        self.project_open = success
        return success

    def compile_project(self, vfpga_top_path: str) -> bool:
        # 1. Open the project (if not already open)
        if not self.open_project():
            return False

        # Check if any file changed and we need to recompile!
        last_info = self._get_last_compile_info()
        latest_modification_time = FSHelper.get_latest_modification_time(
            [TEST_BENCH_FOLDER, SOURCE_FOLDER, vfpga_top_path]
        )
        current_info = CompilationInfo(latest_modification_time, vfpga_top_path)

        if (last_info.get_change_time() < current_info.get_change_time()) or (
            last_info.get_vfpga_file() != current_info.get_vfpga_file()
        ):
            self.logger.info("Recompilation is required.")

            # Copy over the FPGA file
            with open(vfpga_top_path, "r") as src_file:
                with open(SIM_TARGET_V_FPGA_TOP_FILE, "w") as target_file:
                    target_file.write(src_file.read())

            # Compile
            success = self._run_commands(
                [
                    # Increase parallelism for compilation to 16 sub-jobs
                    "set_property -name xsim.compile.xsc.mt_level -value {16} -objects [get_filesets sim_1]",
                    # Set compilation order, Elaborate and compile
                    "update_compile_order -fileset sources_1",
                    "launch_simulation -simset [get_filesets sim_1] -step compile -mode behavioral",
                    "launch_simulation -simset [get_filesets sim_1] -step elaborate -mode behavioral"
                ]
            )
            if success:
                self._safe_current_compile_info(current_info)
            return success

        self.logger.warning(
            "Skipping recompilation as no source code changes were found."
        )
        return True

    def _run_simulation(
        self,
        sim_dump_path,
        simulation_time: SimulationTime,
        disable_randomization: bool,
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
                # Disable the existing var dump in the code as we will use our own!
                "set_value -radix bin /tb_user/VAR_DUMP_ENABLED 0",
                # Disable in& output randomization if this is requested
                f"set_value -radix bin /tb_user/RANDOMIZATION_ENABLED {'0' if disable_randomization else '1'}",
                # Generate VCD dump for the simulation!
                # Note: xsim is inside test.sim/sim_1/behav/xsim
                # -> We need to go up four more levels
                f"open_vcd {UNIT_TEST_FOLDER}/sim_dump.vcd",
                f"log_vcd /tb_user/inst_DUT/{sim_dump_path}*",
                f"run {simulation_time.get_simulation_time()};",
                "close_vcd",
                "close_sim",
            ]
        )

    def run_simulation(
        self,
        vfpga_top_replacement: str,
        sim_dump_path: str,
        simulation_time: SimulationTime,
        disable_randomization: bool,
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
        """
        # Re-compile (lazy)
        if not self.compile_project(vfpga_top_replacement):
            return False

        # Run the actual simulation!
        return self._run_simulation(
            sim_dump_path, simulation_time, disable_randomization
        )

    def __del__(self):
        # terminate the vivado process
        # and close all file descriptor
        self._quit_vivado()
        self.vivado.wait()
        os.close(self.tty_master_fd)
        os.close(self.tty_slave_fd)
