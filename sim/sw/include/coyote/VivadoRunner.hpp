/**
 * This file is part of the Coyote <https://github.com/fpgasystems/Coyote>
 *
 * MIT Licence
 * Copyright (c) 2025, Systems Group, ETH Zurich
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:

 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.

 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#ifndef _COYOTE_VIVADO_RUNNER_HPP_
#define _COYOTE_VIVADO_RUNNER_HPP_

#include <pty.h>
#include <stdio.h>
#include <unistd.h>
#include <cerrno>
#include <cstring>
#include <iostream>
#include <string>
#include <sys/wait.h>
#include <filesystem>
#include <vector>

#include <coyote/Common.hpp>

namespace coyote {

class VivadoRunner {
    const char *COMMAND_PROMPT = "Vivado%"; // Command prompt string that Vivado prints on the terminal whenever it is ready for the next Tcl command
    const int COMMAND_PROMPT_SIZE = 7; // Size of the command prompt string

    const char *sim_dir;

    int master;

    FILE *log_fd;

    int initialize() {
        if (system("which vivado > /dev/null 2>&1")) {
            ERROR("Executable 'vivado' is not available");
            return -1;
        }

        pid_t pid = forkpty(&master, nullptr, nullptr, nullptr);

        if (0 > pid) {
            ERROR(strerror(errno));
            return -1;
        }

        if (pid == 0) { // If this is the child process
            const char *argv[] = {"vivado", "-mode", "tcl", NULL};
            execvp(argv[0], const_cast<char *const *>(argv)); // Replace it with execution of Vivado
        }

        DEBUG("initialize() finished")
        return 0;
    }

    std::string waitTillReady() {
        int match = 0;
        std::string output;

        while (true) {
            char buf[1024];
            ssize_t size = read(master, buf, sizeof(buf));
            if (size <= 0) break;

            output.append(buf, size);

            if (output.size() >= COMMAND_PROMPT_SIZE + 1 &&
                output.compare(output.size() - COMMAND_PROMPT_SIZE - 1,
                               COMMAND_PROMPT_SIZE, COMMAND_PROMPT) == 0) {
                output.erase(output.size() - COMMAND_PROMPT_SIZE);
                break;
            }
        }

        return output;
    }

    std::string executeCommand(std::string command, bool do_wait = true) { // TODO: _run_command catch error stuff
        DEBUG("executeCommand() " << command)
        command.append("\n");
        const char *test = command.c_str();
        ssize_t total_written = 0;
        while (total_written < command.size() + 1) {
            auto written = write(master, test + total_written, command.size() + 1 - total_written);
            if (written == -1) {FATAL("Cannot write to master pseudo ty anymore") std::terminate();}
            total_written += written;
        }
        if (do_wait) return waitTillReady(); else return "";
    }

    int executeCommandWithErrorHandling(std::string command) {
        std::string output = executeCommand("catch {" + command + "} execution_error");
        if (output.substr(output.size() - 3, 1) == "1") { // Error
            auto output = executeCommand("puts $execution_error");
            ERROR(output.substr(0, output.size() - 2))
            return -1;
        }
        return 0;
    }

    int executeCommands(std::vector<std::string> commands) {
        for (auto &command : commands) {
            if (executeCommandWithErrorHandling(command) < 0) return -1;
        }
        return 0;
    }

public:
    VivadoRunner() {}

    ~VivadoRunner() {
        int status = 0;
        executeCommand("quit", false);
        wait(&status);
        DEBUG("Vivado exited with code " << status << "...")
        close(master);
    }

    int openProject(const char *sim_dir) {
        this->sim_dir = sim_dir;
        auto status = initialize();
        if (status < 0) return status;

        waitTillReady();
        std::filesystem::path proj_path(sim_dir);

        for (const auto &entry : std::filesystem::directory_iterator(proj_path)) {
            if (entry.is_regular_file() && entry.path().extension() == ".xpr") {
                proj_path = entry.path();
                break;
            }
        }
        if (proj_path.extension() != ".xpr") {
            FATAL("Could not find *.xpr file in path " << proj_path);
            std::terminate();
        }

        auto result = executeCommandWithErrorHandling("open_project " + proj_path.string());
        DEBUG("Opened project successfully")
        return result;
    }

    int compileProject() {
        return executeCommands({
            "set_property -name xsim.compile.xvlog.more_options -value {-d EN_RANDOMIZATION -d EN_INTERACTIVE} -objects [get_filesets sim_1]",
            "set_property -name xsim.compile.xsc.mt_level -value {16} -objects [get_filesets sim_1]",
            "update_compile_order -fileset sources_1",
            "launch_simulation -simset [get_filesets sim_1] -step compile -noclean_dir -mode behavioral",
            "launch_simulation -simset [get_filesets sim_1] -step elaborate -noclean_dir -mode behavioral"});
    }

    int runSimulation(std::string simulation_time = "-all") { // TODO
        std::filesystem::path vcd_path(sim_dir);
        vcd_path /= "sim_dump.vcd";
        return executeCommands({
            "set_property -name {xsim.simulate.runtime} -value {} -objects [get_filesets sim_1]",
            "launch_simulation -simset [get_filesets sim_1] -step simulate -noclean_dir -mode behavioral",
            "restart",
            "open_vcd " + vcd_path.string(),
            "log_vcd /tb_user/inst_DUT/*",
            "run " + simulation_time,
            "close_vcd",
            "close_sim"});
    }
};

}

#endif
