import subprocess
import os
import pty
from typing import Tuple, List

from .constants import SIM_FOLDER, UNIT_TEST_FOLDER
from .simulation_time import SimulationTime

def _get_env():
    env = os.environ.copy()
    env["TERM"] = "xterm"
    return env

class ProcessRunner():
    def run_bash_script(self, path: str):
        result = subprocess.run(
            [
                "/bin/bash",
                path
            ],
            cwd=os.getcwd(),
            env=_get_env()
        )
        assert result.returncode == 0, f"Running bash script at {path} failed"

    def try_open_file_in_vscode(self, filepath):
        subprocess.run(
            [
                "code",
                "-g",
                filepath
            ],
            env=_get_env(),
            capture_output=False,
            text=False
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
    
    def __init__(self, print_logs: bool = False):
        """
        print_logs = Whether to continuously print logs while the simulation is running.
        """
        # TODO: Assert that UNIT_TEST_PATH is not empty and exists
        # -> Throw some error if it is
        self.vivado = self._create_vivado_process(SIM_FOLDER)
        self.print_logs = print_logs
        self.compilation_id = None
        self.first_call = True
        self.project_open = False

    def _get_opposite_path(self, path: str) -> str:
        levels = path.count("/") + 1  # Count the number of levels
        return "/".join([".."] * levels)  # Construct the opposite path

    def _create_vivado_process(self, folder):
        # We need to emulate a tty for vivado to
        # output "Vivado%", we we can know when the
        # command execution
        self.tty_master_fd, self.tty_slave_fd = pty.openpty()
        return subprocess.Popen(
            ['vivado', '-mode', 'tcl'],
            stdin=self.tty_slave_fd,
            stdout=self.tty_slave_fd,
            # Pipe stderr to stdout to have one stream!
            # -> We will check errors in some other way
            stderr=self.tty_slave_fd,
            text=True,
            cwd=folder,
            env=_get_env(),
            bufsize=1
        )

    def _wait_till_vivado_is_ready(self) -> List[str]:
        """
        Waits till vivado is ready for the next command
        and returns all output lines until then
        """
        # Read the response
        output = []
        while True:
            try:
                # Read at most 1024 bytes out of the master file_descriptor
                lines = os.read(self.tty_master_fd, 1024).decode()
                if (self.print_logs):
                    for line in ''.join(lines).split("\r\n"):
                        print(line)
            except OSError:
                break
            
            if 'Vivado% ' in lines:
                output.append(lines.replace("Vivado% ", ""))
                break

            output.append(lines)
        
        # Create the final output
        final_output = ''.join(output).split("\r\n")
        if (final_output[-1] == ''):
            final_output = final_output[:-1]
        
        return final_output
    
    def _run_in_vivado(self, command) -> List[str]:
        """
        Pipes the given command into std in and
        returns all the output created by the command
        """
        # Send the command
        os.write(self.tty_master_fd, (command + '\n').encode())
        return self._wait_till_vivado_is_ready()

    def _quit_vivado(self):
        os.write(self.tty_master_fd, ("quit\n").encode())

    def _run_command(self, command) -> Tuple[bool, List[str]]:
        """
        Runs the given command and returns:
        Whether the execution was successful, and the output that was created
        """
        error_out = []
        output = self._run_in_vivado(f"catch {{{command}}} execution_error")
        output[0] = command
        if output[-1] == "1":
            # The execution failed!
            error_out.append("ERROR DURING COMMAND:")
            error_out = error_out + self._run_in_vivado("puts $execution_error")[1:]

        final_output = output[:-1] + error_out
        return (output[-1] == "0", final_output)

    def _run_commands(self, commands) -> Tuple[bool, List[str]]:
        output = []

        for command in commands:
            (success, command_out) = self._run_command(command)
            output += command_out

            if not success:
                return (False, output)
        
        return (True, output)

    def open_project(self) -> Tuple[bool, List[str]]:
        """
        Opens the project, if not already open
        """
        if self.project_open:
            return (True, [])
        
        # First command, we need to wait till vivado is ready!
        output = self._wait_till_vivado_is_ready()
        (success, out) = self._run_command("open_project test.xpr")
        self.project_open = success
        output += out
        return (success, output)

    def compile_project(self) -> Tuple[bool, List[str]]:
        # Open the project (if not already open)
        (open_success, output) = self.open_project()
        if not open_success:
            return (False, output)
        
        # First step: Check syntax and set compilation order
        (first_success, first_out) = self._run_commands([
            "update_compile_order -fileset sources_1",
            "check_syntax -fileset sources_1"
        ])
        output += first_out
        if not first_success:
            return (False, output)

        # Third step: Compile and elaborate the design
        (third_success, third_out) =  self._run_commands([
            # No value will only load the simulation without running it (we restart it below)
            # TODO: When do we need to recompile? Will changes be caught now?
            # No they wont. I would suggest a simple directory hash to see when we need to recompile
            "set_property -name {xsim.simulate.runtime} -value {} -objects [get_filesets sim_1]",
            "launch_simulation -simset [get_filesets sim_1] -step compile -noclean_dir -mode behavioral",
            "launch_simulation -simset [get_filesets sim_1] -step elaborate -noclean_dir -mode behavioral",
            # First: pipe output to nowhere since we will re-run the actual simulation!
            # This is needed to:
            # - Allow us to rerun the simulation for the next test
            # - Capture all output in the vcd 
            # -> The VCD cannot be initialized before we launch a simulator and
            #    if we only do it afterward, output is missing.
            f"launch_simulation -simset [get_filesets sim_1] -step simulate -noclean_dir -mode behavioral {'' if self.print_logs else '> /dev/null'}",
        ])
        output += third_out
        return (third_success, output)

    def _run_simulation(self, sim_dump_path, simulation_time: SimulationTime) -> Tuple[bool, List[str]]:
        # We could try the following to enable faster simulations (did not change anything for me):
        #set_property -name {xsim.compile.xvlog.more_options} -value {-d SIM_SPEED_UP} -objects [get_filesets sim_1]
        
        # Ensure path ends in slash
        if sim_dump_path != "" and not sim_dump_path.endswith("/"):
            sim_dump_path += "/"

        return self._run_commands([
            # Restart sim
            # Note: the sim has been started during compilation!
            "restart",
            # Disable the existing var dump in the code as we will use our own!
            "set_value -radix bin /tb_user/VAR_DUMP_ENABLED 0",
            # Generate VCD dump for the simulation!
            # Note: xsim is inside test.sim/sim_1/behav/xsim
            # -> We need to go up four more levels
            f"open_vcd {UNIT_TEST_FOLDER}/sim_dump.vcd",
            f"log_vcd /tb_user/inst_DUT/{sim_dump_path}*",
            f"run {simulation_time.get_simulation_time()};",
            "close_vcd",
            "close_sim"
        ])

    def run_simulation(self, compilation_id, sim_dump_path, simulation_time: SimulationTime) -> Tuple[bool, List[str]]:
        """
        id = compilation id. Should change whenever we need to re-compile.
            e.g. the test runs on different source code
        sim_dump_path = The module path of what should be included in the vcd dump
            e.g., "db_pipeline/inst_filter"
        """
        compile_out = []
        if (compilation_id != self.compilation_id or self.first_call):
            # We need to re-compile
            self.first_call = False
            self.compilation_id = compilation_id
            (success, compile_out) = self.compile_project()
            if not success:
                return (False, compile_out)
        
        # Run the actual simulation!
        (success, sim_out) = self._run_simulation(sim_dump_path, simulation_time)
        return (success, compile_out + sim_out)

    def __del__(self):
        # terminate the vivado process
        # and close all file descriptor
        self._quit_vivado()
        self.vivado.wait()
        os.close(self.tty_master_fd)
        os.close(self.tty_slave_fd)

