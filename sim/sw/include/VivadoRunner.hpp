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

#include "Common.hpp"

namespace fpga {

class VivadoRunner {
    const bool PRINT_LOGS;
    const char *VIVADO = "Vivado% ";
    const int VIVADO_SIZE = 8;

    const char *sim_dir;

    int master;

    int initialize() {
        if (system("which vivado > /dev/null 2>&1")) {
            LOG << "Error: Executable 'vivado' is not available" << std::endl;
            return -1;
        }

        pid_t pid = forkpty(&master, nullptr, nullptr, nullptr);

        if (0 > pid) {
            LOG << "Error: " << strerror(errno) << std::endl;
            return -1;
        }

        if (pid == 0) { // If this is the child process
            const char *argv[] = {"vivado", "-mode", "tcl", NULL};
            execvp(argv[0], const_cast<char *const *>(argv)); // Replace it with execution of Vivado
        }

        LOG << "VivadoRunner: initialize() finished" << std::endl;
        return 0;
    }

    std::string waitTillReady() {
        int match = 0;
        std::string output;

        while (true) {
            char buf[1024];
            auto size = read(master, buf, 1024);
            buf[size] = '\0';
            if (PRINT_LOGS) {
                std::cout << buf;
            }
            output.append(buf);
            
            if (size >= VIVADO_SIZE) {
                match = 0;
            }
            for (int i = match; i < VIVADO_SIZE; i++) {
                if (buf[size - (VIVADO_SIZE - i)] == VIVADO[match]) {
                    match++;
                } else {
                    match = 0;
                }
            }
            if (match == VIVADO_SIZE) {
                output.substr(0, output.size() - VIVADO_SIZE);
                break;
            }
        }

        return output;
    }

    std::string executeCommand(std::string command, bool do_wait = true) { // TODO: _run_command catch error stuff
        LOG << "VivadoRunner: executeCommand() " << command << std::endl;
        command.append("\n");
        const char *test = command.c_str();
        write(master, test, command.size() + 1);
        if (do_wait) return waitTillReady(); else return "";
    }

    int executeCommandWithErrorHandling(std::string command) {
        std::string output = executeCommand("catch {" + command + "} execution_error");
        if (output.substr(output.size() - VIVADO_SIZE - 3, 1) == "1") { // Error
            auto output = executeCommand("puts $execution_error");
            LOG << "VivadoRunner: " << output.substr(0, output.size() - VIVADO_SIZE - 2) << std::endl;
            return -1;
        }

        return 0;
    }

    int executeCommands(std::vector<std::string> commands) {
        for (auto &command : commands) {
            if (!executeCommandWithErrorHandling(command)) return -1;
        }
        return 0;
    }

public:
    VivadoRunner(bool print_logs) : PRINT_LOGS(print_logs) {}

    VivadoRunner() = delete;

    ~VivadoRunner() {
        int status = 0;
        executeCommand("quit", false);
        wait(&status);
        LOG << "Vivado exited with code " << status << "..." << std::endl;
        close(master);
    }

    int openProject(const char *sim_dir, const char *proj_name) {
        this->sim_dir = sim_dir;
        auto status = initialize();
        if (status < 0) return status;

        waitTillReady();
        std::filesystem::path proj_path(sim_dir);
        proj_path /= std::string(proj_name) + ".xpr";
        return executeCommandWithErrorHandling("open_project " + proj_path.string());
    }

    int compileProject() {
        std::vector<std::string> commands = {
            "update_compile_order -fileset sources_1", 
            "check_syntax -fileset sources_1",
            "set_property -name {xsim.simulate.runtime} -value {} -objects [get_filesets sim_1]",
            "launch_simulation -simset [get_filesets sim_1] -step compile -noclean_dir -mode behavioral",
            "launch_simulation -simset [get_filesets sim_1] -step elaborate -noclean_dir -mode behavioral"};
        if (PRINT_LOGS) {
            commands.push_back("launch_simulation -simset [get_filesets sim_1] -step simulate -noclean_dir -mode behavioral");
        } else {
            commands.push_back("launch_simulation -simset [get_filesets sim_1] -step simulate -noclean_dir -mode behavioral > /dev/null");
        }
        return executeCommands(commands);
    }

    int runSimulation(std::string simulation_time = "-all") { // TODO
        std::filesystem::path vcd_path(sim_dir);
        vcd_path /= "sim_dump.vcd";
        return executeCommands({
            "restart",
            "set_value -radix bin /tb_user/VAR_DUMP_ENABLED 0",
            "open_vcd " + vcd_path.string(),
            "log_vcd /tb_user/inst_DUT/*",
            "run " + simulation_time,
            "close_vcd",
            "close_sim"});
    }
};

}
