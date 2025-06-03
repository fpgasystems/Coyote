import subprocess
import os
import pty
import logging
import pickle

from .constants import (
    SIM_FOLDER,
    UNIT_TEST_FOLDER,
    SOURCE_FOLDER,
    TEST_BENCH_FOLDER,
    COMPILE_CHECK_FILE,
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


# A singleton that is only create ONCE for all tests
# This allows us to share the compilation & elaboration
# steps between test to cut down on test run-time!
class VivadoRunner(metaclass=Singleton):
    def __init__(self):
        self.vivado = self._create_vivado_process(SIM_FOLDER)
        self.compilation_id = None
        self.first_call = True
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
            bufsize=1,
        )

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

        # TODO: Still printing last line
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

    def _get_previous_modification_time(self) -> float:
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
                return pickle.load(file)

        except FileNotFoundError:
            return 0

    def _safe_current_modification_time(self, time: float):
        with open(COMPILE_CHECK_FILE, "wb") as file:
            pickle.dump(time, file)

    def open_project(self) -> bool:
        """
        Opens the project, if not already open
        """
        if self.project_open:
            return True

        # First command, we need to wait till vivado is ready!
        self._wait_till_vivado_is_ready()
        success = self._run_command("open_project test.xpr")
        self.project_open = success
        return success

    def compile_project(self) -> bool:
        # 1. Open the project (if not already open)
        if not self.open_project():
            return False

        # Check if any file changed and we need to recompile!
        previous_modification_time = self._get_previous_modification_time()
        latest_modification_time = FSHelper.get_latest_modification_time(
            [TEST_BENCH_FOLDER, SOURCE_FOLDER]
        )

        if previous_modification_time < latest_modification_time:
            self.logger.info("Recompilation is required.")
            success = self._run_commands(
                [
                    # First step: Set compilation order
                    "update_compile_order -fileset sources_1",
                    # Then: Elaborate and compile
                    "launch_simulation -simset [get_filesets sim_1] -step compile -mode behavioral",
                    "launch_simulation -simset [get_filesets sim_1] -step elaborate -mode behavioral",
                ]
            )
            if success:
                self._safe_current_modification_time(latest_modification_time)
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
        compilation_id,
        sim_dump_path: str,
        simulation_time: SimulationTime,
        disable_randomization: bool,
    ) -> bool:
        """
        id = compilation id. Should change whenever we need to re-compile.
            e.g. the test runs on different source code
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
        if compilation_id != self.compilation_id or self.first_call:
            # We need to re-compile
            self.first_call = False
            self.compilation_id = compilation_id
            if not self.compile_project():
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
